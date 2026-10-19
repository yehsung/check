import CheckCore
import CheckMobileShared
import Foundation

// MARK: - 도전 미션 · 받기 — 폰 배선 (서버 20261019120000 · 맥 0.3.58)
//
// 사장님 확정(2026-10-19, 원문): "미션에서 바로 받는게 아니라. 달성하면 받는 버튼이 생기고 그거 누르면 받아지게끔 해줘. 그래야
// 루비를 받는 재미가 더 올라갈거 같아. 기존의 주간 목표시간 달성하는것도 받는 버튼으로 받게 바꿔주고. 3시간마다 루비 3개씩
// 주는것만 따로 버튼 없이 자동으로 지급되는걸로 냅두면 돼" — 도전 미션과 주간 근무 단계는 **달성 → [받기] → 지급**,
// 3시간 랩(+3)은 예전처럼 자동이다(폰은 그 지급을 애초에 부르지 않는다 — `ultra_wallet_sync` 는 폰 금지 목록이다).
//
// 모델 · 디코드 · 계열 접기 · 받음 되돌림 방지는 코어 `Achievements.swift` **한 벌**(맥과 같다)이고 이 파일은 **부르고 옮기기만**
// 한다. 제목 · 보조 문장 · 보상 · 목표 · 순서는 전부 서버 응답이다 — 이 파일과 `MeText` 에 50 · 20 · 10 … 이 없는 것이 설계다
// (서버가 미션을 더해도 앱을 다시 낼 필요가 없게 · 화면이 서버와 다른 숫자를 약속하지 않게).
//
// 폰이 더하는 것은 다섯이다(맥 `WorkTimerStoreAchievements.swift` 와 같은 구조 · 폰 스토어 관례로 옮겼다):
//  ① 박자 — **새 타이머가 없다.** 조회는 나 탭 루트 새로고침(`MeStore.refreshRootIfStale`)에 얹는다: 나 탭이 보일 때 ·
//     당겨서 새로고침(`refreshRoot`) · 탭이 보이는 채로 앱이 앞에 올 때. **그리고 탭이 안 보여도 앱이 앞에 올 때마다**
//     (`MeStore.appDidBecomeActive` — 주간 보상과 똑같이): 받을 보상 수가 **탭 막대 배지**라, 나 탭을 한 번도 열지 않은
//     사람에게도 서야 한다(이 값은 메모리라 콜드 스타트엔 늘 nil 이다 — "아는 것만 다시 읽기"로 걸면 그 사람만 영영 못 본다).
//     스로틀은 다른 덩어리와 같은 60초(`isStale`)다 — 앞에 올 때마다 불러도 서버 호출은 1분에 한 번이다.
//     '떠 있음'은 **띄우는 자리에서** 적는다 — 안에서 적으면 Task 가 돌기 전의 같은 턴 두 번째 호출이 아직 거짓을 보고 또 띄운다
//     (주간 보상에 실측이 적혀 있다: 콜드 스타트 한 번에 세 번 나갔다).
//  ② 받기 — 같은 키는 한 번에 하나(`achievementClaimsInFlight` — 두 번 눌러도 요청 1건) · 전부 받기가 떠 있으면 낱개도 기다린다.
//     성공하면 응답의 상태 · 잔량을 옮기고 **이 호출이 넣은 지급(`claimed_now`)만큼** 연출한다(`missionClaimBursts`).
//     실패하면 **그 줄**이 말한다(`achievementClaimFailedKeys` → `MeText.claimFailed`) — 버튼은 그대로 남아 다시 누르는 것이
//     재시도다. 절 위 안내줄은 쓰지 않는다(맥이 검토에서 버린 방식 — 줄을 밀고, 아래쪽 줄을 누른 사람에겐 스크롤 밖이었다).
//  ③ 순서 — 잔량은 **그 사이 미러에 다른 쓰기가 없었을 때만** 옮긴다(`WeeklyWorkRules.shouldApplyRuby` — 주간과 같은 규약).
//     못 썼는데 받은 게 있으면 상점을 다시 읽어 맞춘다. 받기 **전**에 떠난 조회가 받기 **뒤**에 도착하면 그 조회는 버린다
//     (`MeStore.achievementClaimWriteKey`). 겹친 받기 둘의 답이 뒤바뀌어 와도 받음은 되돌아가지 않는다(`merged(over:)`).
//  ④ 세대 · 순번 가드 — 로그아웃(세대) · 겹친 조회(순번)는 주간 보상과 같은 모양이다.
//  ⑤ 연출 상태 — 화면이 아니라 스토어가 "방금 받았다"를 쥔다(줄은 계열이 다음 단계로 바뀌며 새로 그려진다). 나 탭을 떠나면 비운다.
//
// 판정은 전부 서버가 한다(달성 기록은 cron 1분 + 조회 · 받기의 선정산). 이 파일은 **아무것도 판정하지 않는다** — 진행 · 달성 ·
// 받음을 클라가 세지 않는다.
//
// 이 파일은 `#if os(iOS)` 밖이라 맥 `swift test` 가 진짜 경로를 돌린다(`MeAchievementClaimTests`).

/// 받기 연출 한 번(어느 줄에 · 얼마를 · 몇 번째로). 줄은 `target` 으로 자기 연출을 찾고 `serial` 로 처음부터 다시 그린다
/// (맥 `MissionClaimBurst` 와 같은 뜻 · 같은 자리 규약).
package struct MeClaimBurst: Equatable, Sendable {
    package let serial: Int
    package let target: String
    package let amount: Int

    package init(serial: Int, target: String, amount: Int) {
        self.serial = serial
        self.target = target
        self.amount = max(0, amount)
    }

    /// 도전 미션 줄의 자리 — **계열**이다(콕 10 을 받으면 같은 줄이 콕 50 으로 바뀌어도 연출은 그 줄 위에 남는다).
    package static func achievementTarget(series: String) -> String { "achievement:\(series)" }
    /// 이번 주 근무 줄(카드)의 자리.
    package static let weeklyTarget = "weekly"
}

/// 도전 미션 절을 어떻게 그리는가 — 스토어 값 셋(응답 · 함수 없음 · 실패)에서 **한 곳**(`MeStore.achievementSection`)이 고른다
/// (맥 `AchievementSectionState` 와 같은 갈림).
package enum MeAchievementSection: Equatable, Sendable {
    /// 절이 없다 — 이 서버엔 도전 미션이 없다(404 · PGRST202) 또는 줄이 하나도 없다. 실패 문구도 소제목도 안 그린다.
    case hidden
    /// 아직 한 번도 못 받았다(조회가 떠 있다).
    case loading
    /// 한 번도 못 받았는데 마지막 조회가 실패했다 — 실패 문장 + [다시 시도].
    case failed
    /// 계열마다 한 줄(코어 `seriesRows`) + 받을 것의 수(계열로 접기 **전** — 절 머리 "받을 보상 N개"와 같은 수).
    case loaded(rows: [AchievementStatus.Mission], claimableCount: Int)
}

extension MeStore {
    /// 전부 받기(`achievement_claim(null)`)가 떠 있음을 적는 자리. 미션 키가 아니다(서버 키에 `*` 는 없다).
    package nonisolated static let achievementClaimAllSlot = "*"

    // MARK: 화면 값

    /// 절을 어떻게 그리는가(위 `MeAchievementSection`). 로그인 전 · 함수 없는 서버는 `.hidden`.
    package var achievementSection: MeAchievementSection {
        guard achievementsAvailable, context.session.isSignedIn else { return .hidden }
        if let achievements {
            // 받아 둔 값이 있으면 실패해도 그 값을 그린다(알던 줄을 지우지 않는다 — 주간 카드와 같은 규약).
            let rows = achievements.seriesRows
            return rows.isEmpty ? .hidden : .loaded(rows: rows, claimableCount: achievements.claimableCount)
        }
        return achievementsState.hasFailed ? .failed : .loading
    }

    /// 그릴 줄(계열마다 한 줄). 절이 `.loaded` 가 아니면 빈 배열이다.
    package var achievementRows: [AchievementStatus.Mission] {
        if case .loaded(let rows, _) = achievementSection { return rows }
        return []
    }

    /// 받을 도전 미션 수(계열로 접기 **전** — 콕 10 · 50 을 둘 다 채웠으면 2). 서버에 기능이 없으면 0.
    package var achievementClaimableCount: Int {
        guard achievementsAvailable else { return 0 }
        return achievements?.claimableCount ?? 0
    }

    /// 받을 도전 미션의 루비 합([전부 받기] 버튼의 숫자).
    package var achievementClaimableRuby: Int {
        guard achievementsAvailable else { return 0 }
        return achievements?.claimableRuby ?? 0
    }

    /// 지금 받을 수 있는 것 전부의 수 = 도전 미션 + 이번 주 근무 단계(어느 주든). 배지 · 머리 문구가 같은 수를 말한다.
    package var missionClaimableCount: Int {
        achievementClaimableCount + (weeklyWorkAvailable ? (weeklyWork?.pendingCount ?? 0) : 0)
    }

    /// 이 줄의 [받기]가 떠 있는가(흐려지고 눌리지 않는다). 전부 받기가 떠 있으면 낱개 줄도 떠 있는 것으로 본다.
    package func isClaimingAchievement(_ key: String) -> Bool {
        achievementClaimsInFlight.contains(key) || achievementClaimsInFlight.contains(Self.achievementClaimAllSlot)
    }

    /// 이 줄의 마지막 받기가 실패했는가(그 줄 보조 문장 자리에 `MeText.claimFailed`).
    package func achievementClaimDidFail(_ key: String) -> Bool {
        achievementClaimFailedKeys.contains(key)
    }

    /// 이 계열 줄 위의 받기 연출(없으면 nil).
    package func claimBurst(series: String) -> MeClaimBurst? {
        missionClaimBursts[MeClaimBurst.achievementTarget(series: series)]
    }

    /// 이번 주 근무 카드 위의 받기 연출(없으면 nil).
    package var weeklyClaimBurst: MeClaimBurst? {
        missionClaimBursts[MeClaimBurst.weeklyTarget]
    }

    // MARK: 조회

    /// 낡았으면 읽는다(60초 스로틀). 떠 있으면 겹쳐 띄우지 않는다.
    ///
    /// '떠 있다'를 **띄우는 이 자리에서 바로** 적는 이유는 주간 보상과 같다(`refreshWeeklyWorkIfStale` 주석의 실측) — 안에서
    /// 적으면 Task 가 돌기 전의 같은 턴에 온 두 번째 호출이 아직 거짓을 보고 또 띄운다.
    package func refreshAchievementsIfStale() {
        guard context.session.isSignedIn, !achievementsState.isLoading, isStale(achievementsState) else { return }
        achievementsState.isLoading = true
        launch { [weak self] in await self?.loadAchievements() }
    }

    /// 절의 [다시 시도] — 스로틀 없이 한 번. 떠 있으면 아무것도 하지 않는다(요청 0건).
    package func retryAchievements() {
        guard context.session.isSignedIn, !achievementsState.isLoading else { return }
        achievementsState.isLoading = true
        launch { [weak self] in await self?.loadAchievements() }
    }

    /// `achievements_status()` 한 번. 세대(로그아웃) · 순번(겹친 조회) · 받기 가드.
    package func loadAchievements() async {
        guard context.session.isSignedIn else {
            // 띄우는 자리가 미리 적어 둔 '떠 있음'을 거둔다 — 안 거두면 다음 조회가 영영 안 뜬다.
            achievementsState.isLoading = false
            return
        }
        let serial = nextSerial("achievements")
        let generation = context.generation
        // 루비 미러에 쓴 횟수와 받기를 옮긴 횟수를 **떠날 때** 찍는다(도착했을 때 달라졌으면 이 응답은 그보다 옛 서버다).
        let rubyWriteAtDeparture = context.gomokuHost.rubyWriteSerial
        let claimStamp = writeStamp(Self.achievementClaimWriteKey)
        achievementsState.isLoading = true
        defer { if isCurrent("achievements", serial) { achievementsState.isLoading = false } }
        let service = context.service
        do {
            let status = try await context.withMobileSessionRetry { session in
                try await service.achievementsStatus(accessToken: session.accessToken)
            }
            guard generation == context.generation, isCurrent("achievements", serial) else { return }
            // 떠난 뒤 받기 응답이 옮겨졌다 — 이 답은 받기 **전**의 서버를 말할 수 있다(방금 받은 줄에 [받기]가 다시 선다).
            // 버린다: 받기 응답이 이미 더 새 상태와 잔량을 줬고, 그쪽이 신선도 도장도 찍었다(다시 묻지 않는다).
            guard writeStamp(Self.achievementClaimWriteKey) == claimStamp else { return }
            applyAchievementStatus(status, rubyWriteSerialAtDeparture: rubyWriteAtDeparture)
        } catch {
            guard generation == context.generation, isCurrent("achievements", serial) else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            if MobileDeviceRPC.isMissingFunction(error) {
                // 함수가 없는 서버(db push 전) — 절을 조용히 감추고 스로틀 간격 뒤에 다시 묻는다(앱을 다시 켜지 않아도 열린다).
                // 알던 값도 버린다: 서버가 기능을 거뒀다면 그려 둔 줄 · [받기]는 이제 거짓이다.
                achievementsAvailable = false
                achievements = nil
                achievementsState.hasFailed = false
                achievementsState.loadedAt = context.clock.now()
                return
            }
            // 못 읽었다 — 지난 값을 그대로 둔다(빈 목록으로 지어내지 않는다).
            achievementsState.hasFailed = true
        }
    }

    /// 응답 반영(순수 상태 전이 — 네트워크 없음). 조회 · 받기 둘 다 여기를 지난다.
    ///
    /// `rubyWriteSerialAtDeparture` = 요청이 떠날 때의 `MobileGomokuHost.rubyWriteSerial`. nil 이면 비교하지 않는다(직접 부르는 테스트).
    func applyAchievementStatus(_ status: AchievementStatus, rubyWriteSerialAtDeparture: Int? = nil) {
        achievementsAvailable = true
        achievementsState.hasLoaded = true
        achievementsState.hasFailed = false
        achievementsState.loadedAt = context.clock.now()
        // 받음은 되돌아가지 않는다 — 겹친 받기 둘의 답이 뒤바뀌어 와도(코어 `merged(over:)` 주석의 거짓 버튼).
        achievements = status.merged(over: achievements)

        let departure = rubyWriteSerialAtDeparture ?? context.gomokuHost.rubyWriteSerial
        if WeeklyWorkRules.shouldApplyRuby(server: status.rubyBalance, writeSerialAtDeparture: departure,
                                           currentWriteSerial: context.gomokuHost.rubyWriteSerial),
           let ruby = status.rubyBalance {
            context.gomokuHost.rubyBalance = max(0, ruby)
        } else if status.claimedNowRuby > 0 {
            // 그 사이 다른 쓰기가 있어 이 잔량은 버렸다 — 그런데 루비가 늘었으니 사실을 다시 읽는다(옛 잔량이 화면에 남지 않게).
            launch { [weak self] in await self?.loadShop() }
        }
    }

    // MARK: 받기

    /// 도전 미션 받기. `key` 가 nil 이면 받을 것 전부. **같은 키가 떠 있으면 요청 0건**(버튼을 두 번 눌러도 한 번이다).
    package func claimAchievement(key: String?) {
        guard context.session.isSignedIn, achievementsAvailable else { return }
        let slot = key ?? Self.achievementClaimAllSlot
        // 전부 받기가 떠 있으면 낱개도 기다린다 — 같은 행을 두 요청이 함께 잡지 않게(서버가 막지만 버튼도 흐려 둔다).
        guard !achievementClaimsInFlight.contains(slot),
              !achievementClaimsInFlight.contains(Self.achievementClaimAllSlot) else { return }
        // '떠 있음'은 띄우는 이 자리에서 적는다(같은 턴 두 번째 누름이 또 띄우지 않게 — 조회와 같은 이유).
        achievementClaimsInFlight.insert(slot)
        let generation = context.generation
        let rubyWriteAtDeparture = context.gomokuHost.rubyWriteSerial
        let service = context.service
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.achievementClaimsInFlight.remove(slot) } }
            do {
                let status = try await self.context.withMobileSessionRetry { session in
                    try await service.achievementClaim(accessToken: session.accessToken, key: key)
                }
                guard generation == self.context.generation else { return }
                // 받기를 옮긴다 — 이 뒤에 도착하는 **받기 전** 조회는 버려진다(`loadAchievements` 의 도장 비교).
                self.noteLocalWrite(Self.achievementClaimWriteKey)
                self.applyAchievementStatus(status, rubyWriteSerialAtDeparture: rubyWriteAtDeparture)
                self.markAchievementClaim(key, failed: false)
                self.celebrateAchievementClaims(status)
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                if MobileDeviceRPC.isMissingFunction(error) {
                    // 받기 함수가 없다 = 이 서버엔 받기가 없다(한 마이그레이션이라 조회만 있는 서버는 없다) — 절을 감춘다.
                    self.achievementsAvailable = false
                    self.achievements = nil
                    self.achievementsState.hasFailed = false
                    self.achievementsState.loadedAt = self.context.clock.now()
                    return
                }
                // 실패는 그 줄이 말한다(안내줄로 절을 밀지 않는다). 버튼은 그대로 남아 다시 누르는 것이 재시도다.
                self.markAchievementClaim(key, failed: true)
            }
        }
    }

    /// 받을 것 전부 받기(`achievement_claim(null)`) — 받을 것이 없으면 요청 0건.
    package func claimAllAchievements() {
        guard achievementClaimableCount > 0 else { return }
        claimAchievement(key: nil)
    }

    /// 받기 실패 표시를 세우거나 내린다. `key` 가 nil(전부 받기)이면 지금 받을 수 있는 줄 전부다.
    /// 바뀔 때만 대입한다(관찰 무효화를 괜히 만들지 않게).
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

    /// 이 호출이 넣은 지급만큼 연출한다 — 줄(계열)마다 하나. 넣은 것이 없으면(이미 받음 · 미달성) 아무 말도 안 한다
    /// (그 줄은 위 반영으로 이미 맞는 모양이 됐다).
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
        for entry in perSeries {
            startClaimBurst(target: MeClaimBurst.achievementTarget(series: entry.series), amount: entry.amount)
        }
    }

    // MARK: 연출

    /// 연출 하나를 세운다(순번을 올려 같은 줄의 두 번째 받기도 처음부터 다시 그려지게).
    func startClaimBurst(target: String, amount: Int) {
        guard amount > 0 else { return }
        missionClaimBurstSerial &+= 1
        missionClaimBursts[target] = MeClaimBurst(serial: missionClaimBurstSerial, target: target, amount: amount)
    }

    /// 받기 연출을 비운다(화면을 떠날 때). 비어 있으면 대입하지 않는다.
    package func clearMissionClaimBursts() {
        if !missionClaimBursts.isEmpty { missionClaimBursts = [:] }
    }

    /// 받기 실패 문장을 비운다(화면을 떠날 때 — 다시 열면 화면이 새로 묻는다). 비어 있으면 대입하지 않는다.
    package func clearMissionClaimFailures() {
        if !achievementClaimFailedKeys.isEmpty { achievementClaimFailedKeys = [] }
        if weeklyClaimFailed { weeklyClaimFailed = false }
    }

    /// 나 탭을 떠날 때: 연출과 실패 문장을 걷는다(둘 다 "방금 누른 것"에 대한 말이라 다음에 열 때 남아 있으면 거짓이 된다).
    /// 떠 있는 받기 요청은 끊지 않는다 — 응답은 화면이 없어도 옮겨진다(루비 · 받음).
    func missionsTabDidDisappear() {
        clearMissionClaimBursts()
        clearMissionClaimFailures()
    }
}
