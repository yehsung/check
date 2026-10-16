import CheckCore
import CheckMobileShared
import Foundation

/// 이번 주 누적 근무 보상(v0.3.55 · 폰 1.0.8(19)) — `weekly_work_status()` 를 부르고 옮기기만 한다. 규칙은 `MeWeeklyWork.swift`.
///
/// 언제 읽나: 앱이 앞에 올 때(탭이 안 보여도) · 나 탭이 보일 때 · 당겨서 새로고침 — 셋 다 60초 스로틀(`staleSeconds`).
/// 폰 [근무 종료] 직후는 스로틀 없이 한 번(`weeklyWorkDidChange`). 주가 바뀌었으면(월요일 0시를 넘었으면) 스로틀 없이.
///
/// 이 파일은 `#if os(iOS)` 밖이라 맥 `swift test` 가 진짜 경로를 돌린다(`MeWeeklyWorkStoreTests`).
extension MeStore {
    // MARK: 화면 값

    /// 카드를 세울지: 서버에 함수가 있고 · 값이 있거나 아직 첫 조회 중이거나 첫 조회가 실패했다(자리를 지키고 한 줄만 바꾼다).
    package var showsWeeklyWork: Bool {
        guard weeklyWorkAvailable, context.session.isSignedIn else { return false }
        return weeklyWork != nil || weeklyWorkState.isLoading || weeklyWorkState.hasFailed
    }

    // MARK: 읽기

    /// 낡았으면 읽는다(60초 스로틀 · 주가 바뀌었으면 바로). 떠 있으면 겹쳐 띄우지 않는다.
    package func refreshWeeklyWorkIfStale() {
        guard context.session.isSignedIn, !weeklyWorkState.isLoading else { return }
        let rolled = WeeklyWorkRules.weekHasRolled(weeklyWork, now: context.clock.now())
        guard rolled || isStale(weeklyWorkState) else { return }
        launch { [weak self] in await self?.loadWeeklyWork() }
    }

    /// 근무가 막 끝났다(폰 [근무 종료]) — 스로틀 없이 한 번. 떠 있는 조회는 순번에 밀려 버려진다(종료 전에 떠난 값이라서).
    package func weeklyWorkDidChange() {
        guard context.session.isSignedIn else { return }
        launch { [weak self] in await self?.loadWeeklyWork() }
    }

    /// `weekly_work_status()` 한 번. 세대(로그아웃) · 순번(겹친 조회) 가드.
    package func loadWeeklyWork() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("weekly")
        let generation = context.generation
        // 루비 미러를 떠날 때 찍는다 — 도착했을 때 다른 응답이 바꿔 놓았으면 그쪽이 더 새 값일 수 있다(`shouldApplyRuby`).
        let rubyAtDeparture = context.gomokuHost.rubyBalance
        weeklyWorkState.isLoading = true
        defer { if isCurrent("weekly", serial) { weeklyWorkState.isLoading = false } }
        let service = context.service
        do {
            let status = try await context.withMobileSessionRetry { session in
                try await service.fetchWeeklyWorkStatus(accessToken: session.accessToken)
            }
            guard generation == context.generation, isCurrent("weekly", serial) else { return }
            applyWeeklyWorkStatus(status, rubyAtDeparture: rubyAtDeparture)
        } catch {
            guard generation == context.generation, isCurrent("weekly", serial) else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            if MobileDeviceRPC.isMissingFunction(error) {
                // 함수가 없는 서버(db push 전) — 카드를 접고, 스로틀 간격 뒤에 다시 묻는다(앱을 다시 켜지 않아도 열린다).
                weeklyWorkAvailable = false
                weeklyWork = nil
                weeklyWorkState.hasFailed = false
                weeklyWorkState.loadedAt = context.clock.now()
                return
            }
            // 못 읽었다 — 지난 값을 그대로 둔다(0 시간으로 지어내지 않는다).
            weeklyWorkState.hasFailed = true
        }
    }

    /// 응답을 화면에 옮긴다: 상태 · 루비(더 새 값을 되돌리지 않게) · '받았어요' 알림(+ 햅틱 순번) · 이 기기가 본 칸 저장.
    func applyWeeklyWorkStatus(_ status: WeeklyWorkStatusDTO, rubyAtDeparture: Int?) {
        weeklyWorkAvailable = true
        weeklyWork = status
        weeklyWorkState.hasLoaded = true
        weeklyWorkState.hasFailed = false
        weeklyWorkState.loadedAt = context.clock.now()

        let previous = loadWeeklyWorkSeen()
        let grants = WeeklyWorkRules.newGrants(previous: previous, status: status)
        if let seen = WeeklyWorkRules.seen(after: status) { storeWeeklyWorkSeen(seen) }

        let current = context.gomokuHost.rubyBalance
        if WeeklyWorkRules.shouldApplyRuby(server: status.rubyBalance, atDeparture: rubyAtDeparture, current: current),
           let ruby = status.rubyBalance {
            context.gomokuHost.rubyBalance = ruby
        } else if !grants.isEmpty || !status.grantedNow.isEmpty {
            // 받은 게 있는데 그 사이 미러가 바뀌어 잔량을 못 썼다 — 상점을 다시 읽어 지급이 들어간 잔량으로 맞춘다
            // (나 탭이 뜰 때 상점·주간이 함께 떠서 상점 값이 먼저 내려앉는 흔한 경우).
            launch { [weak self] in await self?.loadShop() }
        }

        guard let notice = WeeklyWorkRules.notice(for: grants) else { return }
        weeklyGrantNotice = notice
        weeklyGrantSerial &+= 1
        weeklyGrantNoticeSeen = isTabVisible
    }

    /// 나 탭을 떠날 때: 본 알림은 걷는다. 안 본 알림(탭이 안 보일 때 들어온 것)은 남긴다.
    func weeklyTabDidDisappear() {
        guard weeklyGrantNoticeSeen else { return }
        weeklyGrantNotice = nil
        weeklyGrantNoticeSeen = false
    }

    // MARK: 이 기기가 본 칸(계정별)

    /// 계정별 키 — 같은 폰에서 계정을 바꿔도 앞 사람의 '본 칸'을 물려받지 않는다.
    private var weeklyWorkSeenKey: String? {
        context.session.userID.map { "aing.me.weeklyWorkSeen.\($0)" }
    }

    private func loadWeeklyWorkSeen() -> WeeklyWorkSeen? {
        guard let key = weeklyWorkSeenKey else { return nil }
        return WeeklyWorkSeen(encoded: context.storage.defaults.string(forKey: key))
    }

    private func storeWeeklyWorkSeen(_ seen: WeeklyWorkSeen) {
        guard let key = weeklyWorkSeenKey else { return }
        context.storage.defaults.set(seen.encoded, forKey: key)
    }
}
