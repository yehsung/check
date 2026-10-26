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
// ── v0.3.64 일일 미션(미니게임 3종 · 1:1 3종 각각 하루 한 판 = 루비 5 · 자정(KST)까지 안 받으면 사라진다) ──
// 폰이 더하는 것은 넷이고, **새 RPC · 새 타이머는 없다** — 일일은 위 박자의 `achievements_status` 응답 최상위 `daily` 에 같이 온다.
//  ⑥ 더해진 박자는 **이벤트 둘**뿐이다: 미니게임 제출 성공(`GamesMiniGameHub.performSubmit`) · 1:1 판이 끝난 것을 처음 본 순간
//     (`MobileAppModel` 이 코어 스토어의 `onMatchFinished` 에 건 줄). 둘 다 `refreshAchievementsAfterGameResult(game:)` 다.
//     · 오늘 그 게임 줄을 이미 채웠으면(받았든 안 받았든) **묻지 않는다** — 하루 첫 판만 나간다.
//     · 이 서버가 일일을 모르면(옛 서버 · 404 로 접힘 · 아직 한 번도 못 읽음) **아예 안 묻는다** — 이 박자는 일일 줄을 위한
//       것이라, 안 막으면 마이그레이션 전 서버에서 판마다 조회가 한 건씩 는다(누적은 제 박자로 읽는다).
//     · 떠 있는 조회가 있으면 그 **옛 답에 합류하지 않는다**(그 조회는 판이 서버에 남기 전에 떠났을 수 있다) — 깃발
//       (`achievementsRefetchAfterGame`)을 세우고 그 조회가 끝난 뒤 정확히 한 번 더 묻는다. 안 하면 "판을 했는데 [받기]가 안 뜬다".
//  ⑦ 받기는 `daily_mission_claim(p_key)` — 누적 받기와 **같은 모양**이되 떠 있음 · 실패 표시를 **따로 센다**
//     (`dailyMissionClaimsInFlight` · `dailyMissionClaimFailedKeys` — 한쪽 실패가 다른 쪽 줄에 실패 문장을 세우면 안 된다).
//     404 · PGRST202 는 "이 서버엔 일일 미션이 없다"로 접는다(`dailyMissionsAvailable` — **일일 절만** 감춘다).
//  ⑧ 날짜 넘김 — 응답의 `reset_at_ms` 를 **서버 시각**(`server_now_ms` 로 잰 시계 차)으로 넘긴 줄은 [받기]를 세우지 않고
//     (코어 `DailyMissionStatus.rows(serverNowMs:)`) 그 키의 받기도 안 나가고 배지도 그 줄을 안 센다.
//     폰은 **백그라운드에서 0시를 넘겨 돌아오는 것이 기본**이라 맥의 리셋 깨우개(타이머) 대신 복귀에서 판정한다
//     (`refreshAchievementsIfDayRolledOver` — `MeStore.appDidBecomeActive` · `refreshRootIfStale`).
//  ⑨ 배지는 일일 + 누적 + 주간이고 **날을 넘긴 일일 줄은 뺀다**(`missionClaimableCount`).
//
// 이 파일은 `#if os(iOS)` 밖이라 맥 `swift test` 가 진짜 경로를 돌린다(`MeAchievementClaimTests` · `MeDailyMissionStoreTests`).

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
    /// 일일 미션 줄의 자리(v0.3.64 — 키마다 한 줄이라 키가 곧 자리다). 누적 자리(`achievement:<계열>`)와 겹치지 않는다.
    package static func dailyTarget(key: String) -> String { "daily:\(key)" }
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

    /// 지금 받을 수 있는 것 전부의 수 = **일일 미션**(v0.3.64 — 날을 넘긴 줄은 안 센다) + 누적 미션 + 이번 주 근무 단계(어느 주든).
    /// 배지 · 머리 문구가 같은 수를 말한다.
    package var missionClaimableCount: Int {
        dailyMissionClaimableCount + achievementClaimableCount + (weeklyWorkAvailable ? (weeklyWork?.pendingCount ?? 0) : 0)
    }

    /// 루트에 [미션] 줄을 세우는가 — 주간·도전 미션 **둘 중 하나라도** 그릴 것이 있을 때. 둘 다 없는 서버(옛 서버 ·
    /// 로그인 전)엔 줄이 없다: 1.0.12 까지 카드 둘이 통째로 빠지던 것과 **같은 규약**이라 빈 줄만 남지 않는다.
    package var showsMissionsRow: Bool {
        showsWeeklyWork || achievementSection != .hidden
    }

    /// 미션 화면이 둘 다 못 그리는가(서버에 둘 다 없다). 줄을 눌러 들어온 뒤 빈 화면이 되는 일은 없지만
    /// (줄 자체가 안 선다), 들어간 **뒤** 서버가 기능을 잃을 수는 있어 화면이 할 말을 갖는다.
    package var missionsPageIsEmpty: Bool {
        !showsWeeklyWork && achievementSection == .hidden
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

    /// 미션 화면 당겨서 새로 고치기 — **이 화면에 있는 것만** 다시 읽는다(루트 전체를 다시 읽지 않는다:
    /// 머리·상점·기록·AI 리밋은 이 화면에 없다). 일일 미션은 `achievements_status()` 응답의 `daily` 라
    /// `loadAchievements()` 하나가 **일일·누적을 같이** 데려온다 — 호출을 더 두지 마라.
    package func refreshMissions() async {
        guard context.session.isSignedIn else { return }
        async let weekly: Void = loadWeeklyWork()
        async let missions: Void = loadAchievements()
        _ = await (weekly, missions)
    }

    /// `achievements_status()` 한 번 **+ 꼬리**: 이 조회가 떠 있는 동안 판이 끝났으면(`achievementsRefetchAfterGame`) 끝난 뒤
    /// 정확히 한 번 더 묻는다(머리말 ⑥). 모든 조회 자리가 이 함수를 지나므로 깃발은 어느 박자로 들어와도 배수된다.
    package func loadAchievements() async {
        await performAchievementsFetch()
        drainAchievementsGameRefetch()
    }

    /// 실제 왕복. 세대(로그아웃) · 순번(겹친 조회) · 받기 가드.
    func performAchievementsFetch() async {
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
        // 서버 시계 − 이 폰 시계(일일 줄의 날짜 넘김을 **서버 시각**으로 판정 — 머리말 ⑧). 서버가 안 알려 주면 이 폰 시계를 믿는다(0).
        achievementsServerClockOffsetMs = status.serverNowMs.map { $0 - Self.epochMs(context.clock.now()) } ?? 0
        // 받기가 404 로 접혔던 서버가 `daily` 를 싣고 왔다 = 기능이 있다(한 마이그레이션이라 조회만 있는 서버는 없다).
        if status.daily != nil, !dailyMissionsAvailable { dailyMissionsAvailable = true }
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
            // 전부 받기가 성공했다 — 이 장부를 통째로 비운다. 여기 적히는 키가 **누적 키뿐**이라 안전하다(일일 실패 문장은
            // `dailyMissionClaimFailedKeys` 라는 다른 장부에 있다 — 인수인계 §5-8). 장부를 한 벌로 합치면 이 한 줄이
            // 일일 줄의 실패 문장까지 조용히 지운다(그 못: `ledgersAreKeptApart`).
            // `keys` 로 못 걷는 까닭: 바로 앞 `applyAchievementStatus` 가 이미 받은 줄을 받을 것에서 뺐다.
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
        if !dailyMissionClaimFailedKeys.isEmpty { dailyMissionClaimFailedKeys = [] }
        if weeklyClaimFailed { weeklyClaimFailed = false }
    }

    /// 나 탭을 떠날 때: 연출과 실패 문장을 걷는다(둘 다 "방금 누른 것"에 대한 말이라 다음에 열 때 남아 있으면 거짓이 된다).
    /// 떠 있는 받기 요청은 끊지 않는다 — 응답은 화면이 없어도 옮겨진다(루비 · 받음).
    func missionsTabDidDisappear() {
        clearMissionClaimBursts()
        clearMissionClaimFailures()
    }
}

// MARK: - 일일 미션 (v0.3.64) — 머리말 ⑥⑦⑧⑨
//
// 여기도 **아무것도 판정하지 않는다**: 진행 · 달성 · 받음은 서버가 센다. 클라가 판정하는 것은 **하루가 끝났는가** 하나뿐이고,
// 그 판정도 응답이 준 `reset_at_ms` 와 `server_now_ms` 로만 한다(폰 시계를 그대로 믿지 않는다 — 시계를 돌려 놓은 폰이
// 어제 [받기]를 오늘 누르거나, 오늘 [받기]를 어제 것으로 지워 버린다).
extension MeStore {
    /// 서버 시각의 추정(밀리초) = 이 폰 시계 + 마지막 응답이 잰 시계 차.
    func estimatedServerNowMs() -> Int { Self.epochMs(context.clock.now()) + achievementsServerClockOffsetMs }

    nonisolated static func epochMs(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1000).rounded(.down)) }

    /// 이 응답의 줄을 판정할 서버 시각. 넘김을 **적어 둔** 응답이면 리셋 시각 아래로 내려가지 않는다(시계 차 추정이 흔들려도
    /// 한 번 내린 [받기]가 되살아나지 않게). ★ 이 읽기가 곧 관찰 등록이다 — `dailyMissionRolloverNoted` 를 쓰면 이 값을 읽은
    /// 줄 · 배지가 다시 그려진다.
    func dailyServerNowMs(_ daily: DailyMissionStatus) -> Int {
        let now = estimatedServerNowMs()
        guard let noted = dailyMissionRolloverNoted, noted == daily.resetAtMs else { return now }
        return max(now, noted)
    }

    // MARK: 화면 값

    /// 일일 절이 그릴 줄. **nil = 절을 통째로 감춘다**(로그인 전 · 이 서버엔 일일 미션이 없다 · 아직 모른다 · 응답에 `daily` 가
    /// 없다 · 줄이 하나도 없다). 누적 · 주간은 이 값과 무관하게 산다.
    /// 하루가 끝난 응답이면 새 날의 모양(진행 0 · [받기] 없음 · 받음 없음)이다(코어 `rows(serverNowMs:)`).
    package var dailyMissionRows: [DailyMissionStatus.Mission]? {
        guard context.session.isSignedIn, achievementsAvailable, dailyMissionsAvailable,
              let daily = achievements?.daily, !daily.missions.isEmpty else { return nil }
        return daily.rows(serverNowMs: dailyServerNowMs(daily))
    }

    /// 받을 수 있는 일일 줄의 수(절 머리 "받을 보상 N개" · 배지의 일일 몫). 날을 넘긴 줄은 안 센다.
    package var dailyMissionClaimableCount: Int {
        dailyMissionRows?.filter(\.row.isClaimable).count ?? 0
    }

    /// 받을 수 있는 일일 줄의 루비 합.
    package var dailyMissionClaimableRuby: Int {
        dailyMissionRows?.filter(\.row.isClaimable).reduce(0) { $0 + $1.row.reward } ?? 0
    }

    /// 일일 절을 어떻게 그리는가(누적 쪽 `achievementSection` 과 같은 꼴 — 갈림은 **한 곳**에서 고른다).
    /// 갈래가 둘뿐인 까닭은 `MeDailyMissionSection` 주석에 있다: 일일은 누적과 **같은 응답**으로 오므로 "불러오는 중 · 실패"
    /// 자리를 미리 잡으면 옛 서버에서 빈 카드가 섰다가 사라진다. 받을 수 · 루비는 **줄에서** 센다(서버가 센 수를 믿지 않는다 —
    /// 날을 넘긴 줄이 빠진 뒤의 수여야 한다).
    package var dailyMissionSection: MeDailyMissionSection {
        guard dailyMissionsAvailable, let rows = dailyMissionRows, !rows.isEmpty else { return .hidden }
        return .loaded(rows: rows, claimableCount: dailyMissionClaimableCount, claimableRuby: dailyMissionClaimableRuby)
    }

    /// 이 일일 줄의 [받기]가 떠 있는가(흐려지고 눌리지 않는다). 누적 받기가 떠 있는 것은 **세지 않는다**(따로 센다).
    package func isClaimingDailyMission(_ key: String) -> Bool {
        dailyMissionClaimsInFlight.contains(key) || dailyMissionClaimsInFlight.contains(Self.achievementClaimAllSlot)
    }

    /// 이 일일 줄의 마지막 받기가 실패했는가(그 줄 보조 문장 자리에 `MeText.claimFailed`).
    package func dailyMissionClaimDidFail(_ key: String) -> Bool {
        dailyMissionClaimFailedKeys.contains(key)
    }

    /// 이 일일 줄 위의 받기 연출(없으면 nil).
    package func dailyClaimBurst(key: String) -> MeClaimBurst? {
        missionClaimBursts[MeClaimBurst.dailyTarget(key: key)]
    }

    // MARK: 날 넘김

    /// 서버 시각으로 이 응답의 하루가 끝났으면 그 사실을 **한 번** 적는다(머리말 ⑧). 적었으면 참.
    /// 아직이거나 · 이미 적었거나 · 일일이 없으면 아무것도 쓰지 않는다(관찰 무효화 0건 · 요청 0건).
    @discardableResult
    package func noteDailyMissionRollover() -> Bool {
        guard let daily = achievements?.daily, let reset = daily.resetAtMs, dailyMissionRolloverNoted != reset,
              daily.hasRolledOver(serverNowMs: estimatedServerNowMs()) else { return false }
        dailyMissionRolloverNoted = reset
        return true
    }

    /// 날을 넘겼으면 그 사실을 적고 **스로틀을 건너뛰어** 새 날을 묻는다. 안 넘겼으면 요청 0건.
    /// 부르는 자리는 둘: 앱이 앞으로 돌아올 때(`appDidBecomeActive` — 폰의 기본 경로) · 나 탭 루트 새로고침(`refreshRootIfStale`).
    func refreshAchievementsIfDayRolledOver() {
        guard noteDailyMissionRollover() else { return }
        retryAchievements()
    }

    // MARK: 판 끝난 뒤 조회(머리말 ⑥)

    /// 게임 한 판이 서버에 남은 직후의 조회. **이벤트로만** 부른다(새 타이머 없음):
    /// 미니게임 제출 성공(`GamesMiniGameHub.performSubmit` — `game` 은 `MiniGameKind` 원시값) ·
    /// 1:1 판이 끝난 것을 처음 본 순간(`MobileAppModel` → 코어 `onMatchFinished` — `gomoku` · `chess` · `tetris_duel`).
    ///  · 오늘 그 게임의 일일 줄을 **이미 채웠으면 요청 0건** — 이 조회로 바뀔 것이 없다(받은 뒤에도 판마다 한 번씩 나가지 않게).
    ///  · 떠 있는 조회가 있으면 요청 0건이되 **깃발을 세운다** — 그 조회는 이 판이 서버에 남기 전에 떠났을 수 있어
    ///    그 답에 합류하면 달성이 다음 박자까지 안 보인다. 끝난 뒤 한 번 더 묻는다.
    ///  · **이 서버가 일일을 모르면 요청 0건** — 일일이 없는 서버(db push 전 · `daily_mission_claim` 이 404 로 접힌 뒤)에서는
    ///    이 조회로 바뀔 것이 아무것도 없는데, 안 막으면 **판을 할 때마다** `achievements_status` 가 한 건씩 더 나간다
    ///    (누적 미션은 판으로 움직이지 않는다 — 그건 제 박자로 읽는다). 아직 한 번도 못 읽어 `daily` 를 모를 때도 마찬가지다:
    ///    그때는 그릴 일일 줄 자체가 없고, 첫 조회는 나 탭 · 복귀 박자가 낸다.
    package func refreshAchievementsAfterGameResult(game: String) {
        guard context.session.isSignedIn, achievementsAvailable, dailyMissionsAvailable,
              let daily = achievements?.daily else { return }
        if daily.rows(serverNowMs: dailyServerNowMs(daily))
            .first(where: { $0.key == DailyMissionStatus.key(game: game) })?.row.achieved == true {
            return
        }
        guard !achievementsState.isLoading else {
            achievementsRefetchAfterGame = true
            return
        }
        achievementsState.isLoading = true
        launch { [weak self] in await self?.loadAchievements() }
    }

    /// 조회 하나가 끝난 꼬리에서 깃발을 배수한다(`loadAchievements`). 깃발이 없으면 아무 일도 없다.
    func drainAchievementsGameRefetch() {
        guard achievementsRefetchAfterGame else { return }
        guard context.session.isSignedIn, achievementsAvailable else {
            // 로그아웃 · 기능 없는 서버 — 물을 곳이 없다. 깃발을 들고 있으면 다음 조회 꼬리에서 엉뚱하게 터진다.
            achievementsRefetchAfterGame = false
            return
        }
        // 다른 조회가 아직 떠 있다(내가 버려진 순번이다) — 그쪽 꼬리가 배수한다.
        guard !achievementsState.isLoading else { return }
        achievementsRefetchAfterGame = false
        achievementsState.isLoading = true
        launch { [weak self] in await self?.loadAchievements() }
    }

    // MARK: 일일 받기(머리말 ⑦)

    /// 일일 미션 받기. `key` 가 nil 이면 오늘 받을 것 전부. **지금 받을 수 있는 줄이 아니면 요청 0건**(하루가 끝났으면 어제 줄은
    /// 받을 수 없다) · 같은 키(또는 전부 받기)가 떠 있어도 0건.
    ///
    /// 받을 수 있던 줄인데 리셋을 넘겨 막혔으면(화면에 어제 [받기]가 남아 있던 순간) 넘김을 적고(버튼이 그 자리에서 내려간다)
    /// 조회를 한 번 부른다 — 새 날의 사실을 가져온다(반응 없는 버튼 금지).
    package func claimDailyMission(key: String?) {
        guard context.session.isSignedIn, achievementsAvailable, dailyMissionsAvailable,
              let daily = achievements?.daily else { return }
        let claimable = daily.claimable(serverNowMs: dailyServerNowMs(daily))
        let wanted = key.map { key in claimable.contains { $0.key == key } } ?? !claimable.isEmpty
        guard wanted else {
            let wasClaimable = key.map { key in daily.mission(key)?.row.isClaimable == true }
                ?? daily.missions.contains(where: \.row.isClaimable)
            if wasClaimable, daily.hasRolledOver(serverNowMs: dailyServerNowMs(daily)) {
                noteDailyMissionRollover()
                retryAchievements()
            }
            return
        }
        let slot = key ?? Self.achievementClaimAllSlot
        // 전부 받기가 떠 있으면 낱개도 기다린다 — 같은 행을 두 요청이 함께 잡지 않게(서버가 막지만 버튼도 흐려 둔다).
        guard !dailyMissionClaimsInFlight.contains(slot),
              !dailyMissionClaimsInFlight.contains(Self.achievementClaimAllSlot) else { return }
        // '떠 있음'은 띄우는 이 자리에서 적는다(같은 턴 두 번째 누름이 또 띄우지 않게 — 누적 받기와 같은 이유).
        dailyMissionClaimsInFlight.insert(slot)
        let generation = context.generation
        let rubyWriteAtDeparture = context.gomokuHost.rubyWriteSerial
        let service = context.service
        launch { [weak self] in
            guard let self else { return }
            defer { if generation == self.context.generation { self.dailyMissionClaimsInFlight.remove(slot) } }
            do {
                let status = try await self.context.withMobileSessionRetry { session in
                    try await service.dailyMissionClaim(accessToken: session.accessToken, key: key)
                }
                guard generation == self.context.generation else { return }
                // 받기를 옮긴다 — 이 뒤에 도착하는 **받기 전** 조회는 버려진다(`performAchievementsFetch` 의 도장 비교).
                // 누적 받기와 같은 도장을 쓴다: 응답이 같은 모양 전체(누적 + 일일 + 잔량)라 늦은 조회가 덮으면 양쪽이 되돌아간다.
                self.noteLocalWrite(Self.achievementClaimWriteKey)
                self.applyAchievementStatus(status, rubyWriteSerialAtDeparture: rubyWriteAtDeparture)
                self.markDailyMissionClaim(key, failed: false)
                self.celebrateDailyMissionClaims(status)
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                if MobileDeviceRPC.isMissingFunction(error) {
                    // 받기 함수가 없다 = 이 서버엔 일일 미션이 없다 — **일일 절만** 접는다(누적 · 주간은 그대로).
                    // 기능이 없는 것을 "받지 못했어요"로 말하지 않는다.
                    self.dailyMissionsAvailable = false
                    return
                }
                // 실패는 그 줄이 말한다(누적과 같은 규약 · 다만 장부는 따로다). 버튼은 그대로 남아 다시 누르는 것이 재시도다.
                self.markDailyMissionClaim(key, failed: true)
            }
        }
    }

    /// 오늘 받을 일일 전부 받기(`daily_mission_claim(null)`) — 받을 것이 없으면 요청 0건.
    ///
    /// ★ 여기서 "받을 것이 있는가"를 **미리 세지 않는다.** 세면 날을 넘긴 순간(`dailyMissionClaimableCount == 0`)
    /// 그냥 돌아와, 화면에 남은 어제 [전부 받기]가 낱개 [받기]와 달리 **반응 없는 버튼**이 된다(넘김을 적지도 · 새 날을 묻지도
    /// 못한다). 판정 · 넘김 처리는 낱개와 **같은 길** 하나(`claimDailyMission(key:)`)가 한다 — 받을 것이 없고 날도 안 넘겼으면
    /// 거기서 요청 0건으로 돌아온다.
    package func claimAllDailyMissions() {
        claimDailyMission(key: nil)
    }

    /// 일일 받기 실패 표시를 세우거나 내린다. `key` 가 nil(전부 받기)이면 지금 받을 수 있는 **일일** 줄 전부다.
    private func markDailyMissionClaim(_ key: String?, failed: Bool) {
        let claimable = achievements?.daily.map { $0.claimable(serverNowMs: dailyServerNowMs($0)).map(\.key) } ?? []
        let keys = key.map { Set([$0]) } ?? Set(claimable)
        var next = dailyMissionClaimFailedKeys
        if failed {
            next.formUnion(keys)
        } else if key == nil {
            // 일일 전부 받기가 성공했다 — **이 장부만** 비운다(누적 줄의 실패 문장은 `achievementClaimFailedKeys` 에 그대로 선다).
            next.removeAll()
        } else {
            next.subtract(keys)
        }
        if next != dailyMissionClaimFailedKeys { dailyMissionClaimFailedKeys = next }
    }

    /// 이 호출이 넣은 **일일** 지급만큼 연출한다 — 줄마다 하나. 넣은 것이 없으면(이미 받음 · 미달성 · 어제 것) 아무 말도 안 한다.
    private func celebrateDailyMissionClaims(_ status: AchievementStatus) {
        for claim in status.claimedNow where claim.reward > 0 {
            startClaimBurst(target: MeClaimBurst.dailyTarget(key: claim.key), amount: claim.reward)
        }
    }
}
