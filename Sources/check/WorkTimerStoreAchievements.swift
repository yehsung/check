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
//
// ── v0.3.64 일일 미션(사용자 결정 2026-10-22 — 미니게임 3종 · 1:1 3종 각각 하루 한 판 = 루비 5, 자정(KST)까지 안 받으면 사라진다) ──
//  ⑥ 조회는 **새 RPC · 새 타이머 없이** 위 박자의 `achievements_status` 응답에 같이 온다(최상위 `daily`). 더해진 박자는 이벤트 둘뿐이다:
//     미니게임 판 제출 성공 · 1:1 판이 끝난(결과를 받은) 순간(`refreshAchievementsAfterGameResult(game:)`). 둘 다
//     · 오늘 그 게임 줄을 이미 채웠으면(받았든 안 받았든) **묻지 않는다** — 하루 첫 판만 나간다(검토 지적 2026-10-22: 받은 뒤에도
//       판마다 settle 을 도는 조회가 한 번씩 더 나갔다).
//     · 떠 있는 조회가 있으면 같이 기다리지 **않고** 그 조회가 끝난 뒤 정확히 한 번 더 묻는다(`achievementsRefetchAfterInFlight`) —
//       떠 있는 조회는 판이 서버에 남기 **전**에 떠났을 수 있다(검토 지적 2026-10-22: 그 옛 답에 합류해 달성이 다음 박자까지 안 보였다).
//       다른 박자(지갑 sync)는 예전처럼 같이 기다린다.
//  ⑦ 받기는 `daily_mission_claim(p_key)` — 누적 받기와 **같은 모양**(같은 키 한 번에 하나 · 실패는 그 줄 · 응답이 상태 · 잔량을 옮김 ·
//     `claimed_now` 만큼 연출)이되 떠 있음 · 실패 표시는 따로 센다(`dailyMissionClaimsInFlight` · `dailyMissionClaimFailedKeys`).
//  ⑧ 날짜 넘김 — 응답의 `reset_at_ms` 를 **서버 시각**(`server_now_ms` 로 잰 시계 차)으로 넘긴 줄은 [받기]를 세우지 않고(코어
//     `DailyMissionStatus.rows(serverNowMs:)`) 그 키의 받기도 안 나간다. 배지도 그 줄을 세지 않는다.
//     시계는 관찰 밖이라 판정만으로는 열린 화면이 다시 그려지지 않는다(검토 지적 2026-10-22 — 팝오버 루트는 초 시계를 일부러 안 본다).
//     그래서 넘긴 사실을 관찰 값 하나(`dailyMissionRolloverNoted`)에 **적는다**(`noteDailyMissionRollover()`). 적는 때는 셋:
//       · 깨우개(`DailyMissionRolloverWake` — 레일 [미션] 칸 뒤의 잎 뷰)가 리셋 시각에 `TimelineView(.explicit)` 로 깨어날 때
//         (뷰 일정이다 — 스토어 타이머 · 요청이 늘지 않는다. 근무 밖이라 티커가 멎은 자정에도 깬다).
//       · 팝오버를 다시 여는 순간(`setMenuPresented(true)` — 닫힌 동안 넘긴 자정).
//       · 화면에 남은 [받기]를 눌렀는데 리셋을 넘겨 막혔을 때 — 그때는 조회도 한 번 부른다(새 날의 사실을 가져온다 · 반응 없는 버튼 금지).

/// 받기 연출 한 번(어느 줄에 · 얼마를 · 몇 번째로). 줄은 `target` 으로 자기 연출을 찾고 `serial` 로 처음부터 다시 그린다.
struct MissionClaimBurst: Equatable, Sendable {
    let serial: Int
    let target: String
    let amount: Int

    /// 도전 미션 줄의 자리(계열 — 콕 10 을 받으면 같은 줄이 콕 50 으로 바뀌어도 연출은 그 줄 위에 남는다).
    static func achievementTarget(series: String) -> String { "achievement:\(series)" }
    /// 이번 주 근무 줄의 자리.
    static let weeklyTarget = "weekly"
    /// 일일 미션 줄의 자리(v0.3.64 — 키마다 한 줄이라 키가 곧 자리다). 누적 미션 자리와 겹치지 않는다.
    static func dailyTarget(key: String) -> String { "daily:\(key)" }
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
        /// 게임 한 판이 서버에 남은 직후(v0.3.64 — 미니게임 제출 성공 · 1:1 판 끝남). 일일 미션이 그 판을 세었는지 묻는다(머리 주석 ⑥).
        case gameResult
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
            // 이 조회가 떠 있는 동안 게임 한 판이 서버에 남았다 — 이 답은 그 판 **전**의 서버일 수 있으니 한 번 더 묻는다(머리 주석 ⑥).
            // 깃발은 하나라 판이 몇 번 끝났든 +1건이다.
            if self.achievementsRefetchAfterInFlight {
                self.achievementsRefetchAfterInFlight = false
                self.refreshAchievements(reason: .gameResult)
            }
        }
        achievementsFetchTask = task
        return task
    }

    /// 게임 한 판이 서버에 남은 직후의 조회(v0.3.64 — 머리 주석 ⑥). **이벤트로만** 부른다: 미니게임 제출 성공
    /// (`performSubmitMiniGameScore` — `game` 은 `MiniGameKind` 원시값) · 1:1 판이 끝난 것을 처음 본 순간(코어 스토어의
    /// `onMatchFinished` — `gomoku` · `chess` · `tetris_duel`).
    ///  · 오늘 그 게임의 일일 줄을 이미 채웠으면 요청 0건(nil) — 이 조회는 일일 미션에 아무것도 바꾸지 못한다. 모르면(아직 못 받았다 ·
    ///    그 줄이 없다 · 하루가 넘어갔다) 묻는다.
    ///  · 떠 있는 조회가 있으면 요청 0건(nil)이되 깃발을 세운다 — 그 조회가 끝나면 한 번 더 묻는다.
    @discardableResult
    func refreshAchievementsAfterGameResult(game: String) -> Task<Void, Never>? {
        guard session != nil else { return nil }
        if let daily = achievements?.daily,
           daily.rows(serverNowMs: dailyServerNowMs(daily)).first(where: { $0.key == DailyMissionStatus.key(game: game) })?.row.achieved == true {
            return nil
        }
        guard achievementsFetchTask == nil else {
            achievementsRefetchAfterInFlight = true
            return nil
        }
        return refreshAchievements(reason: .gameResult)
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
        // 서버 시계 − 이 맥 시계(일일 줄의 날짜 넘김을 서버 시각으로 판정 — 머리 주석 ⑧). 서버 시각이 없으면 이 맥 시계를 믿는다(0).
        achievementsServerClockOffsetMs = status.serverNowMs.map { $0 - Self.epochMs(clock()) } ?? 0
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

    // MARK: 일일 미션 받기(v0.3.64)

    /// 서버 시각의 추정(밀리초) — 이 맥 시계 + 마지막 응답이 잰 시계 차. 일일 줄의 날짜 넘김 판정에만 쓴다.
    func estimatedServerNowMs() -> Int { Self.epochMs(clock()) + achievementsServerClockOffsetMs }

    nonisolated static func epochMs(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1000).rounded(.down)) }

    /// 이 응답의 줄을 판정할 서버 시각. 넘김을 적어 둔 응답이면 리셋 시각 아래로 내려가지 않는다(시계 차 추정이 흔들려도 [받기]가
    /// 되살아나지 않게). **이 읽기가 관찰 등록이다** — `dailyMissionRolloverNoted` 를 쓰면 이 값을 읽은 화면 · 배지가 다시 그려진다.
    func dailyServerNowMs(_ daily: DailyMissionStatus) -> Int {
        let now = estimatedServerNowMs()
        guard let noted = dailyMissionRolloverNoted, noted == daily.resetAtMs else { return now }
        return max(now, noted)
    }

    /// 미션 화면이 그릴 일일 줄. **nil = 감춘다**(서버에 도전 미션이 없다 · 아직 모른다 · 응답에 `daily` 가 없다 — 3시간 줄은 남는다).
    /// 하루가 끝난 응답이면 새 날의 모양(진행 0 · [받기] 없음)이다(코어 `rows(serverNowMs:)`).
    var dailyMissionRows: [DailyMissionStatus.Mission]? {
        guard !achievementsUnavailable, let daily = achievements?.daily, !daily.missions.isEmpty else { return nil }
        return daily.rows(serverNowMs: dailyServerNowMs(daily))
    }

    /// 이 응답의 하루가 끝나는 순간(**이 맥 시계** — 리셋 시각 − 시계 차). 깨우개가 이 시각에 깨어난다. 일일이 없거나 · 리셋을 모르거나 ·
    /// 이미 넘김을 적었으면 nil(깨울 일이 없다).
    var dailyMissionRolloverDate: Date? {
        guard !achievementsUnavailable, let daily = achievements?.daily, !daily.missions.isEmpty,
              let reset = daily.resetAtMs, dailyMissionRolloverNoted != reset else { return nil }
        return Date(timeIntervalSince1970: Double(reset - achievementsServerClockOffsetMs) / 1000)
    }

    /// 서버 시각으로 이 응답의 하루가 끝났으면 그 사실을 **한 번** 적는다(머리 주석 ⑧). 적었으면 참. 아직이거나 · 이미 적었거나 ·
    /// 일일이 없으면 아무것도 쓰지 않는다(관찰 무효화 0). 요청은 내지 않는다.
    @discardableResult
    func noteDailyMissionRollover() -> Bool {
        guard let daily = achievements?.daily, let reset = daily.resetAtMs, dailyMissionRolloverNoted != reset,
              daily.hasRolledOver(serverNowMs: estimatedServerNowMs()) else { return false }
        dailyMissionRolloverNoted = reset
        return true
    }

    /// 일일 미션 받기. `key` 가 nil 이면 오늘 받을 것 전부. **지금 받을 수 있는 줄이 아니면 받기 0건**(하루가 끝났으면 어제 줄은 받을
    /// 수 없다 — 머리 주석 ⑧) · 같은 키가 떠 있어도 0건. 발사했으면 그 Task 를 돌려준다(테스트가 기다린다).
    ///
    /// 응답으로는 받을 수 있던 줄인데 리셋을 넘겨 막혔으면(화면에 어제 [받기]가 남아 있던 순간) 넘김을 적고(버튼이 그 자리에서
    /// 내려간다) 조회를 한 번 부른다(새 날의 사실 — 반응 없는 버튼 금지 · 검토 지적 2026-10-22). 그때도 돌려주는 값은 nil 이다(받기는 안 나갔다).
    @discardableResult
    func claimDailyMission(key: String?) -> Task<Void, Never>? {
        guard session != nil, !achievementsUnavailable, let daily = achievements?.daily else { return nil }
        let claimable = daily.claimable(serverNowMs: dailyServerNowMs(daily))
        let wanted = key.map { key in claimable.contains(where: { $0.key == key }) } ?? !claimable.isEmpty
        guard wanted else {
            let wasClaimable = key.map { key in daily.mission(key)?.row.isClaimable == true }
                ?? daily.missions.contains(where: \.row.isClaimable)
            if wasClaimable, daily.hasRolledOver(serverNowMs: dailyServerNowMs(daily)) {
                noteDailyMissionRollover()
                refreshAchievements(reason: .missionPanel)
            }
            return nil
        }
        let slot = key ?? Self.achievementClaimAllSlot
        guard !dailyMissionClaimsInFlight.contains(slot),
              !dailyMissionClaimsInFlight.contains(Self.achievementClaimAllSlot) else { return nil }
        dailyMissionClaimsInFlight.insert(slot)
        let generation = sessionGeneration
        let rubySerial = rubyBalanceWriteSerial
        return Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.sessionGeneration { self.dailyMissionClaimsInFlight.remove(slot) }
            }
            do {
                let status = try await self.withSessionRetry { activeSession in
                    try await self.service.dailyMissionClaim(accessToken: activeSession.accessToken, key: key)
                }
                guard generation == self.sessionGeneration else { return }
                self.applyAchievements(status, rubyWriteSerialAtDeparture: rubySerial)
                self.markDailyMissionClaim(key, failed: false)
                self.celebrateDailyMissionClaims(status)
            } catch {
                if case .cancelled = self.classifyAuthError(error) { return }
                guard generation == self.sessionGeneration else { return }
                // 실패는 그 줄이 말한다(누적 줄과 같은 규약 — 버튼은 그대로 남아 다시 누르는 것이 재시도다).
                self.markDailyMissionClaim(key, failed: true)
            }
        }
    }

    /// 일일 받기 실패 표시를 세우거나 내린다. `key` 가 nil(전부 받기)이면 지금 받을 수 있는 일일 줄 전부다.
    private func markDailyMissionClaim(_ key: String?, failed: Bool) {
        let claimable = achievements?.daily.map { $0.claimable(serverNowMs: dailyServerNowMs($0)).map(\.key) } ?? []
        let keys = key.map { Set([$0]) } ?? Set(claimable)
        var next = dailyMissionClaimFailedKeys
        if failed {
            next.formUnion(keys)
        } else if key == nil {
            next.removeAll()
        } else {
            next.subtract(keys)
        }
        if next != dailyMissionClaimFailedKeys { dailyMissionClaimFailedKeys = next }
    }

    /// 이 호출이 넣은 일일 지급만큼 연출한다 — 줄마다 하나 · 캐릭터 말풍선은 합계로 한 번. 넣은 것이 없으면 조용하다.
    private func celebrateDailyMissionClaims(_ status: AchievementStatus) {
        let paid = status.claimedNow.filter { $0.reward > 0 }
        guard !paid.isEmpty else { return }
        for claim in paid {
            startClaimBurst(target: MissionClaimBurst.dailyTarget(key: claim.key), amount: claim.reward)
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
        if !dailyMissionClaimFailedKeys.isEmpty { dailyMissionClaimFailedKeys = [] }
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

    /// 레일 [미션] 칸의 숫자 = 받을 일일 미션 수(v0.3.64 — 하루가 끝난 줄은 안 센다) + 받을 누적 미션 수(계열로 접기 전 — 콕 10 · 50 을
    /// 둘 다 채웠으면 2) + 받을 주간 단계 수(어느 주든). 서버에 도전 미션이 없으면 앞의 둘은 0 이다(옛 서버 주간 응답도 0 — 받기가 없다).
    var missionClaimableCount: Int {
        let achievementCount = achievementsUnavailable ? 0 : (achievements?.claimableCount ?? 0)
        let dailyCount = achievementsUnavailable ? 0 : (achievements?.daily.map { $0.claimableCount(serverNowMs: dailyServerNowMs($0)) } ?? 0)
        return dailyCount + achievementCount + (weeklyWork?.pendingCount ?? 0)
    }
}
