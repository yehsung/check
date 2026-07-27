import Foundation

// 개인 기록(히트맵·주간 회고) + 토큰 순위 월 이동 + 넛지 자동시작 취소의 스토어 계층.
// 데이터 출처는 서버 work_sessions 의 내 완료 세션뿐이고(타인 데이터 미조회), 요일/주 계산은 전부
// CheckWorkInsights 의 순수 함수가 담당한다(스토어는 로딩·상태 반영만).
@MainActor
extension WorkTimerStore {
    /// 히트맵 집계 기간(주). 이 기간의 완료 세션만 서버에서 받아 온다.
    static let insightsWeeks = 8
    /// 넛지 자동 시작을 취소할 수 있는 유예(초). 이 시간 안에는 헤더에 [취소] 가 뜬다.
    static let nudgeAutoStartCancelWindow: TimeInterval = 60
    /// 이 주의 회고 배너를 이미 보여줬는지 기록하는 UserDefaults 키의 앞자리(계정별 접미사가 붙는다).
    static let retroBannerShownWeekKey = "check.retro.shownForWeek"
    /// 넛지 자동시작 토글의 UserDefaults 키.
    static let nudgeAutoStartEnabledKey = "check.nudgeAutoStartEnabled"
    /// 이 맥의 기기 식별자 UserDefaults 키(토큰 원장 분리용).
    static let deviceIDKey = "check.deviceID"

    /// 개인 기록 조회 창의 시작(KST). 히트맵 8주 창의 첫 월요일 00:00 — 회고가 보는 '지난주+그 전주'(2주)를
    /// 완전히 포함하므로 두 계산이 한 번의 조회를 나눠 쓴다.
    static func insightsWindowStart(now: Date = Date()) -> Date {
        let weekStart = TeamWeeklyGoal.koreanWeekStart(for: now)
        return TeamWeeklyGoal.kstCalendar.date(
            byAdding: .weekOfYear,
            value: -(insightsWeeks - 1),
            to: weekStart
        ) ?? weekStart
    }

    /// 이 맥의 기기 식별자를 읽고, 없으면 한 번 만들어 저장한다(결함1 — 맥별 토큰 원장 분리 키).
    /// init 에서만 부르며, 이후 재실행에도 같은 값이 유지돼 같은 기기의 행이 계속 갱신된다.
    static func resolveDeviceID(defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: deviceIDKey), !stored.isEmpty {
            return stored
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: deviceIDKey)
        return generated
    }

    /// 넛지 자동시작 설정의 초기값을 정한다(결함1 — 업데이트만으로 기존 의사가 뒤집히지 않게).
    /// 키 `check.nudgeAutoStartEnabled` 는 v0.2.11 에서 처음 생긴다. 없다고 무조건 true 로 시드하면,
    /// v0.2.10 까지 넛지 자격이 `isOverlayEnabled` 를 AND 로 걸고 있어서 **캐릭터를 숨긴 사용자에게는
    /// 자동 근무 시작이 아예 일어나지 않던** 사실이 무시된다 — 그들은 '캐릭터 끔 = 앱이 알아서 시작하지 않음'으로
    /// 써 왔는데, 업데이트만으로 동의 없이 자동 시작이 켜지고(팀원 화면엔 '근무중'으로 노출), 하필 그 상태에선
    /// 등장 말풍선도 안 뜨고 [취소] 배너는 60초 안에 팝오버를 열어야만 보여 통지가 가장 약하다.
    /// 그래서 키가 없을 때 한 번만 캐릭터 표시 설정을 그대로 승계하고, 그 값을 즉시 저장해 그 뒤로는
    /// 캐릭터를 다시 켜든 말든 흔들리지 않는 독립 토글로 운용한다.
    static func resolveNudgeAutoStartEnabled(defaults: UserDefaults) -> Bool {
        if let stored = defaults.object(forKey: nudgeAutoStartEnabledKey) as? Bool {
            return stored
        }
        let inherited = defaults.object(forKey: overlayEnabledKey) as? Bool ?? true
        defaults.set(inherited, forKey: nudgeAutoStartEnabledKey)
        return inherited
    }

    /// 개인 기록 패널 로드 래퍼(Task 발사). 패널을 여는 순간·팝오버 재오픈에서 호출한다.
    func loadInsights() {
        Task { @MainActor in await performLoadInsights() }
    }

    /// 내 최근 완료 세션을 받아 히트맵/회고를 계산해 반영한다.
    /// 표준 로딩 관례: session 가드 → sessionGeneration 캡처 → withSessionRetry → 응답 반영 시 generation 재확인
    /// → 등호 가드 대입 → 취소 에러 조용히. 실패해도 문구를 흔들지 않는다(다음 재오픈에서 재시도).
    func performLoadInsights() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        let since = Self.insightsWindowStart()
        // 주 경계를 넘긴 뒤의 재계산이라면, 손에 든 heatmap/retro 는 '지난주'가 아니라 지지난주 집계다 — 먼저 버린다.
        discardInsightsIfWeekRolledOver()
        // 재시도가 시작되면 직전 실패 표시를 내린다 — 패널이 다시 "불러오는 중…"으로 돌아가야
        // 사용자가 [다시 시도]를 눌렀다는 사실이 화면에 보인다.
        if insightsFailed { insightsFailed = false }
        do {
            let rows = try await withSessionRetry { activeSession in
                try await service.fetchMySessions(
                    accessToken: activeSession.accessToken,
                    userID: activeSession.userID,
                    since: since
                )
            }
            guard generation == sessionGeneration else { return }
            let now = Date()
            // 계산은 메인액터 밖에서 한다. 히트맵·회고는 세션마다 타임스탬프를 파싱하고 시간/일 경계로 쪼개는
            // 순수 CPU 작업이라, 세션이 많은 계정(자리 비움 자동 마감이 잦으면 8주에 수백~수천 건)에서는
            // 메인액터에 올려 두면 응답이 도착하는 순간 UI 가 통째로 멈춘다 — 서버 limit 상한인 2000행에서
            // 350ms(60Hz 기준 21프레임) 이상 점유했다. 결과만 받아 대입하므로 메인액터 점유는 상수 시간이다.
            let weeks = Self.insightsWeeks
            let goalSeconds = teamGoalSeconds
            // 진행 중인 내 세션은 서버 조회(ended_at not null)에 안 잡히므로 여기서 얹어 준다. 헤더 캡션이
            // 진행분을 더한 이번 주 누적을 세는 동안 패널만 "아직 기록이 쌓이지 않았어요"라고 말하던
            // 조합(=완료 세션 0건인 가입 첫날 근무 중)이 이 한 줄로 사라진다. 이 값을 넘겨도 이중 계상은
            // 없다 — 그 세션이 끝나 완료 행이 되면 startedAt 은 이미 nil 이다.
            let ongoingStart = startedAt
            let computed = await Task.detached(priority: .userInitiated) {
                WorkInsightsComputation.build(rows: rows, now: now, weeks: weeks, goalSeconds: goalSeconds, ongoingStart: ongoingStart)
            }.value
            // 계산 동안 로그아웃/재로그인이 끼어들 수 있다 — 대입 직전에 세대를 한 번 더 확인한다.
            guard generation == sessionGeneration else { return }
            if heatmap != computed.heatmap { heatmap = computed.heatmap }
            if retro != computed.retro { retro = computed.retro }
            if !insightsLoaded { insightsLoaded = true }
            if insightsFailed { insightsFailed = false }
            // 이 결과가 어느 주 기준인지 남긴다 — 앱을 켜 둔 채 주가 바뀌면 팝오버 오픈 훅이 재계산을 건다.
            insightsWeekKey = RetroWeekKey.current(now)
            evaluateRetroBanner()
        } catch {
            // 취소(팝오버 빨리 닫기 등)는 실패가 아니다 — 표시를 흔들지 않고 조용히 빠져나간다.
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            // 그 외 실패는 반드시 표시로 남긴다. 예전엔 아무 상태도 세우지 않아 패널이 "불러오는 중…"에
            // 영원히 멈춰(진행중과 실패가 같은 문구) 사용자가 재시도할 방법도, 판단할 근거도 없었다.
            // 토큰 보드가 이미 쓰는 대칭(진행중 vs 로드완료 vs 실패)을 개인 기록에도 맞춘다.
            if !insightsFailed { insightsFailed = true }
        }
    }

    /// 주가 바뀐 뒤 남아 있는 '이전 주 기준' 계산 결과를 버린다(재계산 시작 시 1회).
    /// WeeklyRetro 는 계산 시점의 now 로 대상 주를 확정하므로, 앱을 켜 둔 채 주말을 넘기면 store.retro 는
    /// 지지난주 집계가 된다. 예전엔 재계산이 실패해도(월요일 아침 Wi-Fi 미연결 등) 그 값을 그대로 뒀는데,
    /// 뷰는 (로드 완료 + 누적>0) 이면 실패 표시도 [다시 시도]도 없이 본문을 그리고(InsightsEmptyMessage.text),
    /// 회고 카드에는 대상 주 날짜가 어디에도 없어 2주 전 합계가 "지난주 8시간 40분"으로 **지난주인 척** 보였다.
    /// 그래서 낡은 값은 조회를 시작하는 순간 버린다 — 성공하면 새 주 기준으로 다시 채워지고, 실패하면
    /// 0건 상태와 같은 경로("기록을 불러오지 못했어요" + [다시 시도])로 떨어진다.
    func discardInsightsIfWeekRolledOver(now: Date = Date()) {
        guard let key = insightsWeekKey, key != RetroWeekKey.current(now) else { return }
        insightsWeekKey = nil
        // 이 스냅샷은 더 이상 '로드된 결과'가 아니다 — 실패 시 뷰가 로딩/실패 문구 쪽으로 갈라지게 한다.
        if insightsLoaded { insightsLoaded = false }
        if heatmap != .empty { heatmap = .empty }
        if retro != nil { retro = nil }
        // 배너도 내린다 — [보기]를 눌러도 지금 보여 줄 회고가 없다. 이번 주 키는 소비하지 않으므로
        // 재계산이 성공하면 evaluateRetroBanner 가 새 회고로 다시 판정한다.
        if showsRetroBanner { showsRetroBanner = false }
    }

    /// 팀 목표가 뒤늦게 확정/변경됐을 때 이미 계산해 둔 회고의 목표선을 따라가게 한다.
    /// teamGoalSeconds 는 UserDefaults 에 남지 않아 기본값(TeamWeeklyGoal.defaultGoalSeconds)으로 시작하고
    /// 멤버십 응답에서야 서버값이 되는데, 팝오버 오픈 훅은 그보다 먼저 loadInsights 를 발사한다 — 그렇게 굳은
    /// retro 는 insightsWeekKey 때문에 그 주 내내 재계산되지 않아 '목표 달성'이 '몇 시간 부족'으로 뒤집혔다(회귀 지점).
    /// 목표에 의존하는 값은 goalSeconds/metGoal 뿐이라 세션 재조회 없이 사본으로 갈아 끼운다.
    func reconcileInsightsGoal() {
        guard let current = retro, current.goalSeconds != teamGoalSeconds else { return }
        retro = current.withGoal(teamGoalSeconds)
    }

    /// 이 계정의 '이번 주 회고 배너 봤음' 키. 회고는 명백히 계정별 상태인데 전역 키 하나를 쓰던 시절엔,
    /// 같은 맥에서 A 로 배너를 소비하고 로그아웃한 뒤 같은 주에 B 로 로그인하면 B 가 그 주 내내 회고 배너를
    /// 한 번도 못 받았다(로그아웃은 이 키를 지우지 않는다 — 지워 버리면 반대로 A 가 같은 주에 또 받는다).
    /// 세션이 없을 때는(로그인 전) 예전 전역 키를 그대로 쓴다 — 그 상태에선 배너를 띄울 회고 자체가 없다.
    var retroBannerShownWeekKeyForCurrentUser: String {
        guard let userID = session?.userID, !userID.isEmpty else { return Self.retroBannerShownWeekKey }
        return "\(Self.retroBannerShownWeekKey).\(userID)"
    }

    /// 팝오버 열림 시 회고 배너 노출 여부를 판정한다(주당 1회, 지난주 근무가 있을 때만).
    /// 보여줄 회고가 없거나 이번 주 키를 이미 소비했으면 배너를 내린다.
    /// 개인 기록 패널을 이미 보고 있으면 배너를 띄우지 않는다 — 회고 카드가 그 패널 안에 상시 있어 중복이고,
    /// 배너가 겹치면 팝오버 높이만 밀어 올린다(이번 주 키는 소비 처리해 다시 뜨지 않게 한다).
    func evaluateRetroBanner() {
        guard !isInsightsPanelVisible else {
            // 회고가 실제로 있을 때만 '봤음'으로 소비한다(빈 패널을 열어 둔 것만으로 이번 주 안내를 잃지 않게).
            if retro != nil {
                markRetroBannerSeen()
            } else if showsRetroBanner {
                showsRetroBanner = false
            }
            return
        }
        guard retro != nil else {
            if showsRetroBanner { showsRetroBanner = false }
            return
        }
        guard defaults.string(forKey: retroBannerShownWeekKeyForCurrentUser) != RetroWeekKey.current() else {
            // 이번 주 몫은 이미 소비됐다. 다만 지금 팝오버에 떠 있는 배너가 바로 그 노출이라면(같은 세션에서
            // markRetroBannerDisplayed 가 기록한 직후) 도중에 걷어내지 않는다 — 팝오버가 닫힐 때 내려간다.
            if showsRetroBanner, isMenuPresented { return }
            if showsRetroBanner { showsRetroBanner = false }
            return
        }
        if !showsRetroBanner { showsRetroBanner = true }
    }

    /// 회고 배너가 팝오버에 **실제로 그려진** 순간 이번 주 몫을 소비한다(뷰의 onAppear 가 부른다).
    /// 예전엔 어디에서도 소비하지 않아, 사용자가 [보기]나 X 를 누르지 않으면 팝오버를 열 때마다(setMenuPresented →
    /// evaluateRetroBanner) 같은 배너가 다시 떴다 — '주당 1회' 계약 위반이자, '배너는 한 번에 하나' 규칙 때문에
    /// 회고가 상주하는 동안 새 버전 안내 배너(앱 안에서 업데이트로 가는 유일한 경로)가 그 주 내내 막혔다.
    /// 판정(evaluateRetroBanner)이 아니라 **표시** 시점에 소비하는 이유는, 더 급한 배너가 그 자리를 이겨
    /// 회고가 화면에 뜨지도 못한 팝오버에서 이번 주 안내를 잃지 않게 하기 위해서다(밀린 배너는 다음에 뜬다).
    func markRetroBannerDisplayed() {
        guard showsRetroBanner else { return }
        defaults.set(RetroWeekKey.current(), forKey: retroBannerShownWeekKeyForCurrentUser)
    }

    /// 회고 배너를 이번 주에 본 것으로 기록하고 감춘다(배너 닫기/개인 기록 패널 진입 공통 경로).
    func markRetroBannerSeen() {
        defaults.set(RetroWeekKey.current(), forKey: retroBannerShownWeekKeyForCurrentUser)
        if showsRetroBanner { showsRetroBanner = false }
    }

    /// 토큰 순위판 월 이동(-1=과거, +1=미래). 이동 후 그 달 보드를 다시 로드한다.
    /// 현재 월보다 미래로는 못 가므로(네비게이터가 클램프) 값이 그대로면 아무 요청도 발사하지 않는다.
    func stepTokenBoardMonth(by delta: Int) {
        let next = TokenBoardMonthNavigator.step(tokenBoardMonth, by: delta)
        guard next != tokenBoardMonth else { return }
        tokenBoardMonth = next
        // 이전 달 행이 잠깐 남아 '이번 달인 척' 보이지 않도록 비우고 로드 전 상태로 되돌린다.
        tokenBoard = []
        tokenBoardLoaded = false
        // 응답이 오기 전 빈 목록 자리에 동기화 문구("동기화됨")가 아니라 "불러오는 중…"이 뜨게 한다.
        // (loadTokenBoard 가 Task 를 발사하므로 여기서 먼저 세워야 첫 프레임부터 올바른 문구가 보인다.)
        tokenBoardLoading = true
        // 직전 달에서 실패한 표시도 함께 내린다 — 새 달 조회의 첫 프레임에 남의 실패 문구를 물려주지 않는다.
        if tokenBoardFailed { tokenBoardFailed = false }
        loadTokenBoard()
    }

    /// 넛지 자동 시작 사용 여부를 지정하고 설정을 저장한다(결함5 — 자동시작을 캐릭터 표시와 분리해 끌 수 있게).
    func setNudgeAutoStartEnabled(_ enabled: Bool) {
        if isNudgeAutoStartEnabled != enabled { isNudgeAutoStartEnabled = enabled }
        defaults.set(enabled, forKey: Self.nudgeAutoStartEnabledKey)
    }

    /// 자동 시작 취소 가능 여부(자동 시작 직후 유예 안, 아직 근무중).
    func canCancelNudgeAutoStart(now: Date = Date()) -> Bool {
        guard let startedAt = nudgeAutoStartedAt, startedAt != Date.distantPast else { return false }
        guard self.startedAt != nil else { return false }
        return now.timeIntervalSince(startedAt) <= Self.nudgeAutoStartCancelWindow
    }

    /// 넛지가 자동 시작한 근무를 취소한다(= 근무 종료 + 안내). 유예를 벗어났거나 이미 종료했으면 무동작.
    /// stop() 이 세대 토큰을 올리고 서버 반영 큐까지 태우므로, "묻지 않고 시작한" 판단이 되돌려진다.
    func cancelNudgeAutoStart() {
        guard canCancelNudgeAutoStart() else { return }
        stop()
        nudgeAutoStartedAt = nil
        syncMessage = "자동 시작을 취소했어요"
    }
}
