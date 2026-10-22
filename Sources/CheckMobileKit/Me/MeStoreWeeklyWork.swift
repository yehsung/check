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

    /// [받기 +N] 을 세우는가(v0.3.58) — 받기 서버이고 받을 단계가 있다. 옛 서버(`supportsClaim == false`)는 언제나 거짓이다.
    package var showsWeeklyClaim: Bool {
        guard showsWeeklyWork else { return false }
        return weeklyWork?.hasClaimable == true
    }

    /// 버튼의 숫자 — 받을 루비 합(어느 주든). 받을 것이 없으면 0.
    package var weeklyClaimableRuby: Int {
        guard weeklyWorkAvailable else { return 0 }
        return weeklyWork?.pendingRuby ?? 0
    }

    /// 지금 누를 수 있는가(떠 있는 받기가 없고 받을 것이 있다).
    package var canClaimWeeklyWork: Bool {
        !weeklyClaimInFlight && showsWeeklyClaim
    }

    // MARK: 읽기

    /// 낡았으면 읽는다(60초 스로틀 · 주가 바뀌었으면 바로). 떠 있으면 겹쳐 띄우지 않는다.
    ///
    /// '떠 있다'는 **띄우는 이 자리에서 바로** 적는다. `loadWeeklyWork` 안에서 적으면 Task 가 돌기 전의 같은 턴에 온 두 번째
    /// 호출이 아직 거짓을 보고 또 띄운다 — 앞에 올 때(`appDidBecomeActive` 가 직접 한 번 + `refreshRootIfStale` 이 한 번)마다
    /// 두 번, 콜드 스타트(탭 표시 + 활성화)엔 세 번 나갔다(검토 지적 2026-10-16). 하나하나가 서버에서 지갑 자물쇠를 잡는 정산이다.
    package func refreshWeeklyWorkIfStale() {
        guard context.session.isSignedIn, !weeklyWorkState.isLoading else { return }
        let rolled = WeeklyWorkRules.weekHasRolled(weeklyWork, now: context.clock.now())
        guard rolled || isStale(weeklyWorkState) else { return }
        weeklyWorkState.isLoading = true
        launch { [weak self] in await self?.loadWeeklyWork() }
    }

    /// 근무가 막 끝났다(폰 [근무 종료]) — 스로틀 없이 한 번. 떠 있는 조회는 순번에 밀려 버려진다(종료 전에 떠난 값이라서).
    package func weeklyWorkDidChange() {
        guard context.session.isSignedIn else { return }
        launch { [weak self] in await self?.loadWeeklyWork() }
    }

    /// `weekly_work_status()` 한 번. 세대(로그아웃) · 순번(겹친 조회) 가드.
    package func loadWeeklyWork() async {
        guard context.session.isSignedIn else {
            // 띄우는 자리(`refreshWeeklyWorkIfStale`)가 미리 적어 둔 '떠 있음'을 거둔다 — 안 거두면 다음 조회가 영영 안 뜬다.
            weeklyWorkState.isLoading = false
            return
        }
        let serial = nextSerial("weekly")
        let generation = context.generation
        // 루비 미러에 쓴 횟수를 떠날 때 찍는다 — 도착했을 때 그 사이 누가 썼으면 그쪽이 더 새 값일 수 있다(`shouldApplyRuby`).
        let rubyWriteAtDeparture = context.gomokuHost.rubyWriteSerial
        // 받기를 옮긴 횟수도 찍는다(v0.3.58) — 받기 뒤에 도착한 **받기 전** 조회를 덮어쓰기에서 막는다.
        let claimStamp = writeStamp(Self.weeklyClaimWriteKey)
        weeklyWorkState.isLoading = true
        defer { if isCurrent("weekly", serial) { weeklyWorkState.isLoading = false } }
        let service = context.service
        do {
            let status = try await context.withMobileSessionRetry { session in
                try await service.weeklyWorkStatus(accessToken: session.accessToken)
            }
            guard generation == context.generation, isCurrent("weekly", serial) else { return }
            // 떠난 뒤 받기 응답이 옮겨졌다 — 이 답은 받기 **전**의 서버를 말할 수 있다(방금 받은 단계에 [받기]가 다시 선다).
            // 버린다: 받기 응답이 이미 더 새 상태 · 잔량을 줬고 신선도 도장도 찍었다.
            guard writeStamp(Self.weeklyClaimWriteKey) == claimStamp else { return }
            applyWeeklyWorkStatus(status, rubyWriteSerialAtDeparture: rubyWriteAtDeparture)
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
    func applyWeeklyWorkStatus(_ status: WeeklyWorkStatus, rubyWriteSerialAtDeparture: Int) {
        weeklyWorkAvailable = true
        // 카드를 그릴 만큼 모르는 응답(누적초 · 칸 표가 빠진 서버 어긋남)은 **알던 값을 덮지 않는다** — 맥 줄과 같은 규약
        // (`WeeklyWorkStatus.isUsable`). 모르는 누적초를 0 으로 그리면 "이번 주 0시간"이라는 거짓말이 된다.
        if status.isUsable { weeklyWork = status }
        weeklyWorkState.hasLoaded = true
        weeklyWorkState.hasFailed = false
        weeklyWorkState.loadedAt = context.clock.now()

        let previous = loadWeeklyWorkSeen()
        let grants = WeeklyWorkRules.newGrants(previous: previous, status: status)
        // 본 기록도 칸 표를 알 때만 옮긴다 — 표가 빠진 응답으로 '본 칸 없음'을 적으면 다음 조회가 받은 칸을 다 새로 알린다.
        if !status.tiers.isEmpty, let seen = WeeklyWorkRules.seen(after: status) { storeWeeklyWorkSeen(seen) }

        if WeeklyWorkRules.shouldApplyRuby(server: status.rubyBalance, writeSerialAtDeparture: rubyWriteSerialAtDeparture,
                                           currentWriteSerial: context.gomokuHost.rubyWriteSerial),
           let ruby = status.rubyBalance {
            context.gomokuHost.rubyBalance = ruby
        } else if !grants.isEmpty || !status.grantedNow.isEmpty || !status.claimedNow.isEmpty {
            // 받은 게 있는데 그 사이 미러가 바뀌어 잔량을 못 썼다 — 상점을 다시 읽어 지급이 들어간 잔량으로 맞춘다
            // (나 탭이 뜰 때 상점·주간이 함께 떠서 상점 값이 먼저 내려앉는 흔한 경우).
            launch { [weak self] in await self?.loadShop() }
        }

        guard let notice = WeeklyWorkRules.notice(for: grants) else { return }
        weeklyGrantNotice = notice
        weeklyGrantSerial &+= 1
        weeklyGrantNoticeSeen = isTabVisible
    }

    // MARK: 받기 (v0.3.58 — 사장님 2026-10-19 "기존의 주간 목표시간 달성하는것도 받는 버튼으로 받게 바꿔주고")

    /// 이번 주 근무 받기 — **받을 것 전부(어느 주든)** 한 번에(`weekly_work_claim(null, null)`). 떠 있으면 요청 0건,
    /// 받을 것이 없으면(옛 서버 포함) 나가지 않는다.
    ///
    /// 받음을 알리는 것은 **연출**이다(`MeClaimBurst.weeklyTarget` + `missionClaimBurstSerial` 햅틱). 자동 지급 칩
    /// (`weeklyGrantNotice`)은 쓰지 않는다 — 받기 서버에서 `claimed` 가 거짓 → 참이 되는 길은 사람이 [받기]를 누른 것뿐이라
    /// 그걸 "N시간 채웠어요"로 또 말하면 같은 일을 두 번 알린다(맥 `newlyGranted` 와 같은 판단).
    package func claimWeeklyWork() {
        guard context.session.isSignedIn, !weeklyClaimInFlight, weeklyWork?.hasClaimable == true else { return }
        // '떠 있음'은 띄우는 이 자리에서 적는다(같은 턴 두 번째 누름이 또 띄우지 않게).
        weeklyClaimInFlight = true
        let generation = context.generation
        let rubyWriteAtDeparture = context.gomokuHost.rubyWriteSerial
        let service = context.service
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.weeklyClaimInFlight = false } }
            do {
                let status = try await self.context.withMobileSessionRetry { session in
                    try await service.weeklyWorkClaim(accessToken: session.accessToken)
                }
                guard generation == self.context.generation else { return }
                // 받기 전에 떠난 주간 조회가 이 뒤에 도착하면 버린다(`loadWeeklyWork` 의 도장 비교).
                self.noteLocalWrite(Self.weeklyClaimWriteKey)
                self.applyWeeklyWorkStatus(status, rubyWriteSerialAtDeparture: rubyWriteAtDeparture)
                if self.weeklyClaimFailed { self.weeklyClaimFailed = false }
                // 이 호출이 **실제로 넣은** 지급만큼 연출한다(이미 받았거나 미달이면 서버가 `claimed_now: []` 를 주고 아무 말도 안 한다).
                self.startClaimBurst(target: MeClaimBurst.weeklyTarget, amount: status.claimedNowRuby)
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                // 함수 없음(404)도 여기서는 그냥 실패다(맥 `claimWeeklyWork` 와 같다) — 버튼을 세우는 `supportsClaim` 은
                // 상태 응답이 말하고 상태 · 받기는 한 마이그레이션이라, "상태엔 받을 것이 있는데 받기 함수가 없다"는 서버는 없다.
                // 조용히 삼키면 누른 사람에게 아무 일도 안 일어난다 — 그게 더 나쁘다.
                // 실패는 주간 줄이 말한다(도전 미션과 같은 규약 — 안내줄로 카드를 밀지 않는다).
                if !self.weeklyClaimFailed { self.weeklyClaimFailed = true }
            }
        }
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
