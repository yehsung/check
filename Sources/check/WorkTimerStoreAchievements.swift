import CheckCore
import Foundation

// MARK: - 도전 미션 · 받기 — 맥 배선 (v0.3.58)
//
// 사장님 확정(2026-10-19, 원문): "미션에서 바로 받는게 아니라. 달성하면 받는 버튼이 생기고 그거 누르면 받아지게끔 해줘. 그래야
// 루비를 받는 재미가 더 올라갈거 같아. 기존의 주간 목표시간 달성하는것도 받는 버튼으로 받게 바꿔주고. 3시간마다 루비 3개씩
// 주는것만 따로 버튼 없이 자동으로 지급되는걸로 냅두면 돼" — 도전 미션과 주간 근무 단계는 **달성 → [받기] → 지급**,
// 3시간 랩(+3 · `ultra_wallet_sync`)은 예전처럼 자동이다(이 파일은 그쪽을 건드리지 않는다).
//
// 규칙 · 디코드 · 계열 접기는 코어 `Achievements.swift` · `WeeklyWorkReward.swift` 에 있다. 맥이 더하는 것은 다섯이다:
//  ① 박자 — **새 타이머가 없다.** 도전 미션 조회는 지갑 sync(`syncUltraWallet(reason:)`)에 얹는다:
//       · `.panelOpen` 이면서 **미션 화면이 떠 있을 때만** — 레일 [미션]으로 여는 순간 · 그 화면의 [다시 시도] · 미션 화면을 연 채
//         팝오버를 다시 연 순간(`setMenuPresented(true)`) 셋이 전부 이 모양으로 지갑을 부른다. 콕찌르기 · 울트라 화면을 여는 `.panelOpen`
//         은 묻지 않는다(그 화면엔 도전 미션이 없다).
//       · `.periodic` — 근무 중 5분 스로틀(`syncUltraWalletIfDue`)이 이미 막아 둔 박자라 5분에 많아야 하나 더다.
//       · `.signIn` — 로그인 · 저장 세션 활성화 직후 한 번(실행마다 1건). 검토 지적(2026-10-19)으로 더했다: 레일 배지는 [받기]를
//         찾는 길인데, 이것이 없으면 근무를 안 하는 사람의 배지는 소급 달성(설계 추정 52명 중 41명 · 약 9,920 루비)을 영영 말하지 않고
//         근무하는 사람도 첫 5분 sync 까지 몰랐다. 첫 [미션] 열기의 "불러오는 중…"도 대부분 사라진다. 여전히 타이머는 없다.
//     겹친 박자는 떠 있는 조회 하나를 같이 기다린다(`achievementsFetchTask`). 받기는 사람이 누를 때만 나간다.
//  ② 받기 — 같은 키는 한 번에 하나(`achievementClaimsInFlight` — 두 번 눌러도 요청 1건) · 주간은 전부 받기 하나(`weeklyClaimInFlight`).
//     성공하면 응답의 상태 · 잔량을 옮기고 **이 호출이 넣은 지급(`claimed_now`)만큼** 연출한다(`missionClaimBursts` + 캐릭터 말풍선).
//     실패하면 **그 줄**이 보조 문장 자리에 실패 문장을 그린다(`achievementClaimFailedKeys` · `weeklyClaimFailed`) — 버튼은 그대로 남아
//     다시 누르는 것이 재시도다. 안내줄(`missionNotice`)은 쓰지 않는다(검토 지적 2026-10-19: 안내줄은 절 위에 끼어 줄을 26pt 밀고,
//     넷째 줄부터는 누른 사람의 스크롤 밖이라 안 보였고, 다시 받아 내리면 연출 중에 줄이 위로 뛰었다).
//  ③ 순서 — 잔량은 **그 사이 다른 쓰기가 없었을 때만** 옮긴다(`rubyBalanceWriteSerial` — 주간 보상과 같은 규약). 받기 전에 떠난 조회가
//     받기 뒤에 도착하면 그 조회는 버린다(`achievementsApplySerial` · `weeklyClaimSerial`). 겹친 받기 둘의 답이 뒤바뀌어 와도 받음은
//     되돌아가지 않는다(`AchievementStatus.merged(over:)`).
//  ④ 배지 — 레일 [미션] 칸의 숫자 = 받을 도전 미션 수 + 받을 주간 단계 수(`missionClaimableCount`). 본 적 있는지 따위는 적지 않는다
//     — 받으면 내려간다.
//  ⑤ 연출 상태 — 화면이 아니라 스토어가 "방금 받았다"를 쥔다(줄은 계열이 다음 단계로 바뀌며 새로 그려지기 때문이다). 미션 화면 ·
//     팝오버를 닫으면 비운다.
//
// 판정은 서버가 한다(달성 기록은 cron 1분 + 조회 · 받기의 선정산). 이 파일은 **아무것도 판정하지 않는다.**

/// 받기 연출 한 번(어느 줄에 · 얼마를 · 몇 번째로). 줄은 `target` 으로 자기 연출을 찾고 `serial` 로 처음부터 다시 그린다.
struct MissionClaimBurst: Equatable, Sendable {
    let serial: Int
    let target: String
    let amount: Int

    /// 도전 미션 줄의 자리(계열 — 콕 10 을 받으면 같은 줄이 콕 50 으로 바뀌어도 연출은 그 줄 위에 남는다).
    static func achievementTarget(series: String) -> String { "achievement:\(series)" }
    /// 이번 주 근무 줄의 자리.
    static let weeklyTarget = "weekly"
}

extension WorkTimerStore {
    /// 도전 미션 조회를 부르는 이유. 진단 문자열이 아니라 호출 지점의 목록이다.
    enum AchievementsFetchReason: String, Equatable, Sendable {
        /// 미션 화면을 보는 순간(열기 · [다시 시도] · 연 채 팝오버 재오픈 — 셋 다 `.panelOpen` 지갑 sync 를 탄다).
        case missionPanel
        /// 근무 중 5분 지갑 sync 에 얹힌 박자.
        case periodic
        /// 로그인 · 저장 세션 활성화 직후 지갑 sync 에 얹힌 한 번(레일 배지가 패널을 안 열어도 켜진다 — 머리 주석 ①).
        case signIn
    }

    /// 전부 받기(`achievement_claim(null)`)가 떠 있음을 적는 자리. 키가 아니다(서버 키에 `*` 는 없다).
    nonisolated static let achievementClaimAllSlot = "*"

    /// 지갑 sync 박자 → 도전 미션 박자. 미션 화면이 아닌 `.panelOpen`(콕찌르기 · 울트라)과 랩 임계는 묻지 않는다.
    func achievementsReason(forWallet reason: UltraSyncReason) -> AchievementsFetchReason? {
        switch reason {
        case .panelOpen: return isMissionPanelVisible ? .missionPanel : nil
        case .periodic: return .periodic
        case .signIn: return .signIn
        case .missionCandidate: return nil
        }
    }

    // MARK: 조회

    /// 발사 판정 + 발사. 발사했으면 그 Task 를 돌려준다(테스트가 기다린다). 떠 있는 조회가 있으면 **요청 0건**이다.
    @discardableResult
    func refreshAchievements(reason: AchievementsFetchReason) -> Task<Void, Never>? {
        guard session != nil else { return nil }
        guard achievementsFetchTask == nil else { return nil }
        let generation = sessionGeneration
        let task = Task { @MainActor [weak self] in
            await self?.performAchievementsFetch()
            guard let self, generation == self.sessionGeneration else { return }
            self.achievementsFetchTask = nil
        }
        achievementsFetchTask = task
        return task
    }

    /// 실제 왕복. 함수가 없는 서버(404 · PGRST202)는 절을 감추고, 그 밖의 실패는 **알던 값을 지우지 않는다** — 다음 박자가 다시 묻는다.
    func performAchievementsFetch() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        let rubySerial = rubyBalanceWriteSerial
        let applySerial = achievementsApplySerial
        do {
            let status = try await withSessionRetry { activeSession in
                try await service.achievementsStatus(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            // 떠난 뒤 받기 응답이 옮겨졌다 — 이 답은 받기 **전**의 서버를 말할 수 있다(방금 받은 줄에 [받기]가 다시 선다). 버린다.
            // 받기 응답이 이미 더 새 상태를 줬으니 다시 묻지 않는다.
            guard applySerial == achievementsApplySerial else { return }
            applyAchievements(status, rubyWriteSerialAtDeparture: rubySerial)
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            if let known = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(known) {
                markAchievementsUnavailable()
                return
            }
            if !achievementsFailed { achievementsFailed = true }
        }
    }

    /// 이 서버엔 도전 미션이 없다 — 실패가 아니다. 알던 값도 버린다(서버가 기능을 거둔 것이니 그린 줄 · 버튼은 이제 거짓이다).
    private func markAchievementsUnavailable() {
        if !achievementsUnavailable { achievementsUnavailable = true }
        if achievementsFailed { achievementsFailed = false }
        if achievements != nil { achievements = nil }
    }

    /// 응답 반영(순수 상태 전이 — 네트워크 없음). 조회 · 받기 둘 다 여기를 지난다. 테스트가 이 한 함수로 규칙을 고정한다.
    ///
    /// `rubyWriteSerialAtDeparture` = 요청이 떠날 때의 `rubyBalanceWriteSerial`. nil 이면 비교하지 않는다(직접 부르는 테스트).
    func applyAchievements(_ status: AchievementStatus, rubyWriteSerialAtDeparture: Int? = nil) {
        achievementsApplySerial &+= 1
        if let ruby = status.rubyBalance {
            let untouched = rubyWriteSerialAtDeparture.map { $0 == rubyBalanceWriteSerial } ?? true
            if untouched {
                let normalized = max(0, ruby)
                if rubyBalance != normalized { rubyBalance = normalized }
                // 잔량을 옮겼으면 **언제나** 상점 변이로 적는다 — 그 전에 떠난 상점 조회가 늦게 와서 받기 전 잔량으로 덮지 않게
                // (`applyWeeklyWork` 와 같은 이유 · 같은 줄).
                noteShopMutation()
            } else if status.claimedNowRuby > 0 {
                // 그 사이 다른 쓰기가 있어 이 값은 버렸다 — 그런데 루비가 늘었으니 사실을 다시 읽는다(옛 잔량이 화면에 남지 않게).
                loadShopState()
            }
        }
        if achievementsUnavailable { achievementsUnavailable = false }
        if achievementsFailed { achievementsFailed = false }
        // 받음은 되돌아가지 않는다(겹친 받기 둘의 답이 뒤바뀌어 와도 — `merged(over:)` 주석).
        let merged = status.merged(over: achievements)
        if achievements != merged { achievements = merged }
    }

    // MARK: 받기

    /// 도전 미션 받기. `key` 가 nil 이면 받을 것 전부. **같은 키가 떠 있으면 요청 0건**(nil 을 돌려준다) — 버튼을 두 번 눌러도 한 번이다.
    /// 발사했으면 그 Task 를 돌려준다(테스트가 기다린다).
    @discardableResult
    func claimAchievement(key: String?) -> Task<Void, Never>? {
        guard session != nil, !achievementsUnavailable else { return nil }
        let slot = key ?? Self.achievementClaimAllSlot
        // 전부 받기가 떠 있으면 낱개도 기다린다(같은 행을 두 요청이 함께 잡지 않게 — 서버가 막지만 버튼도 흐려 둔다).
        guard !achievementClaimsInFlight.contains(slot),
              !achievementClaimsInFlight.contains(Self.achievementClaimAllSlot) else { return nil }
        achievementClaimsInFlight.insert(slot)
        let generation = sessionGeneration
        let rubySerial = rubyBalanceWriteSerial
        return Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.sessionGeneration { self.achievementClaimsInFlight.remove(slot) }
            }
            do {
                let status = try await self.withSessionRetry { activeSession in
                    try await self.service.achievementClaim(accessToken: activeSession.accessToken, key: key)
                }
                guard generation == self.sessionGeneration else { return }
                self.applyAchievements(status, rubyWriteSerialAtDeparture: rubySerial)
                self.markAchievementClaim(key, failed: false)
                self.celebrateAchievementClaims(status)
            } catch {
                if case .cancelled = self.classifyAuthError(error) { return }
                guard generation == self.sessionGeneration else { return }
                if let known = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(known) {
                    // 받기 함수가 없다 = 이 서버엔 받기 서버가 없다(한 마이그레이션이라 조회만 있는 서버는 없다) — 절을 감춘다.
                    self.markAchievementsUnavailable()
                    return
                }
                // 실패는 그 줄이 말한다(머리 주석 ② — 안내줄로 절을 밀지 않는다).
                self.markAchievementClaim(key, failed: true)
            }
        }
    }

    /// 받기 실패 표시를 세우거나 내린다. `key` 가 nil(전부 받기)이면 지금 받을 수 있는 줄 전부다. 바뀔 때만 대입한다(관찰 무효화를
    /// 만들지 않게).
    private func markAchievementClaim(_ key: String?, failed: Bool) {
        let keys = key.map { Set([$0]) } ?? Set(achievements?.claimable.map(\.key) ?? [])
        var next = achievementClaimFailedKeys
        if failed {
            next.formUnion(keys)
        } else if key == nil {
            next.removeAll()
        } else {
            next.subtract(keys)
        }
        if next != achievementClaimFailedKeys { achievementClaimFailedKeys = next }
    }

    /// 이 호출이 넣은 지급만큼 연출한다 — 줄(계열)마다 하나 · 캐릭터 말풍선은 합계로 한 번. 넣은 것이 없으면(이미 받음 · 미달성)
    /// 아무 말도 안 한다(그 줄은 위 반영으로 이미 맞는 모양이 됐다).
    private func celebrateAchievementClaims(_ status: AchievementStatus) {
        var perSeries: [(series: String, amount: Int)] = []
        for claim in status.claimedNow where claim.reward > 0 {
            let series = status.series(ofKey: claim.key) ?? claim.key
            if let index = perSeries.firstIndex(where: { $0.series == series }) {
                perSeries[index].amount += claim.reward
            } else {
                perSeries.append((series, claim.reward))
            }
        }
        guard !perSeries.isEmpty else { return }
        for entry in perSeries {
            startClaimBurst(target: MissionClaimBurst.achievementTarget(series: entry.series), amount: entry.amount)
        }
        onRewardTrigger?(.rubyReward(amount: status.claimedNowRuby))
    }

    /// 이번 주 근무 받기 — **받을 것 전부(어느 주든)** 한 번에. 떠 있으면 요청 0건. 받을 것이 없으면(옛 서버 포함) 나가지 않는다.
    @discardableResult
    func claimWeeklyWork() -> Task<Void, Never>? {
        guard session != nil, !weeklyClaimInFlight, weeklyWork?.hasClaimable == true else { return nil }
        weeklyClaimInFlight = true
        let generation = sessionGeneration
        let rubySerial = rubyBalanceWriteSerial
        return Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.sessionGeneration { self.weeklyClaimInFlight = false }
            }
            do {
                let status = try await self.withSessionRetry { activeSession in
                    try await self.service.weeklyWorkClaim(accessToken: activeSession.accessToken)
                }
                guard generation == self.sessionGeneration else { return }
                // 받기 전에 떠난 주간 조회가 이 뒤에 도착하면 버린다(`performWeeklyWorkFetch`).
                self.weeklyClaimSerial &+= 1
                self.applyWeeklyWork(status, rubyWriteSerialAtDeparture: rubySerial)
                if self.weeklyClaimFailed { self.weeklyClaimFailed = false }
                let amount = status.claimedNowRuby
                guard amount > 0 else { return }
                self.startClaimBurst(target: MissionClaimBurst.weeklyTarget, amount: amount)
                self.onRewardTrigger?(.rubyReward(amount: amount))
            } catch {
                if case .cancelled = self.classifyAuthError(error) { return }
                guard generation == self.sessionGeneration else { return }
                // 실패는 주간 줄이 말한다(도전 미션과 같은 규약 — 안내줄로 절을 밀지 않는다).
                if !self.weeklyClaimFailed { self.weeklyClaimFailed = true }
            }
        }
    }

    // MARK: 연출 · 배지

    /// 받기 실패 문장을 비운다(미션 화면 · 팝오버를 닫을 때 — 다시 열면 화면이 새로 묻는다). 비어 있으면 대입하지 않는다.
    func clearMissionClaimFailures() {
        if !achievementClaimFailedKeys.isEmpty { achievementClaimFailedKeys = [] }
        if weeklyClaimFailed { weeklyClaimFailed = false }
    }

    private func startClaimBurst(target: String, amount: Int) {
        missionClaimBurstSerial &+= 1
        missionClaimBursts[target] = MissionClaimBurst(serial: missionClaimBurstSerial, target: target, amount: amount)
    }

    /// 받기 연출을 비운다(미션 화면 · 팝오버를 닫을 때). 비어 있으면 대입하지 않는다(관찰 무효화를 만들지 않게).
    func clearMissionClaimBursts() {
        if !missionClaimBursts.isEmpty { missionClaimBursts = [:] }
    }

    /// 레일 [미션] 칸의 숫자 = 받을 도전 미션 수(계열로 접기 전 — 콕 10 · 50 을 둘 다 채웠으면 2) + 받을 주간 단계 수(어느 주든).
    /// 서버에 도전 미션이 없으면 그쪽은 0 이다(옛 서버 주간 응답도 0 — 받기가 없다).
    var missionClaimableCount: Int {
        let achievementCount = achievementsUnavailable ? 0 : (achievements?.claimableCount ?? 0)
        return achievementCount + (weeklyWork?.pendingCount ?? 0)
    }
}
