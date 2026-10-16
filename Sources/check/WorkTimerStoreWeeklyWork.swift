import CheckCore
import Foundation

// MARK: - 주간 누적 근무 보상 — 맥 배선 (v0.3.55)
//
// 규칙·디코드·"새로 받은 단계" 판정은 코어 `WeeklyWorkReward.swift`(폰과 한 벌)에 있다. 맥이 더하는 것은 셋뿐이다:
//  ① 박자 — 지갑 sync 와 **같은 박자**(로그인 · 패널 열기 · 랩 임계 · 근무 중 5분)에 얹고, 근무가 끝난 직후 한 번 더 묻는다.
//     다만 어떤 이유로든 **1분에 한 번을 넘지 않는다**(`weeklyWorkMinIntervalSeconds`). 근무 종료 직후의 조회가 그 창에 막히면
//     빚(`weeklyWorkFetchOwed`)으로 남기고 폴링 tick 이 1분이 지나면 갚는다 — 막힌 채 버리면 종료 직후 넘긴 단계를 다음 근무까지 모른다.
//     예외 하나: 마지막 조회 뒤 월요일 0시(KST)를 넘었으면 창을 건너뛰고(폴링 tick 도 한 번 묻는다) 지난주 줄을 새 주로 바꾼다.
//  ② 거울 — 응답의 `ruby_balance` 는 **그 사이 다른 쓰기가 없었을 때만** 옮긴다(`rubyBalanceWriteSerial`). 떠난 뒤 뽑기·대국 정산이
//     새 잔량을 썼는데 이 응답이 나중에 도착해 덮으면 잔량이 한 판 전으로 돌아간다.
//  ③ 알림 — 새로 받은 단계가 있으면 3시간 랩과 **같은 두 자리**로 말한다: 울트라 화면의 안내줄(`missionNotice`)과 캐릭터 말풍선
//     (`onRewardTrigger` — "루비 +N!"). 새 토스트 장치를 만들지 않는다.
//
// 지급 자체는 서버(cron 1분 + 이 조회의 선정산)가 한다. 이 파일은 **아무것도 판정하지 않는다** — 시간을 재서 "넘었다"고 말하지 않는다.

extension WorkTimerStore {
    /// 주간 조회 사이의 최소 간격(초). 어떤 이유든 이보다 자주 묻지 않는다(무료 플랜 · 서버가 어차피 1분마다 정산한다).
    static let weeklyWorkMinIntervalSeconds: TimeInterval = 60

    /// 주간 조회를 부르는 이유. 진단 문자열이 아니라 호출 지점의 목록이다.
    enum WeeklyWorkFetchReason: String, Equatable, Sendable {
        /// 지갑 sync 와 같은 박자(`syncUltraWallet(reason:)` 이 함께 부른다).
        case walletCadence
        /// 근무가 끝난 직후(수동 종료 · 자동 마감 — 종료 기록이 서버에 닿은 뒤). 1분 창에 막히면 빚으로 남는다.
        case workEnded
        /// 남은 빚을 폴링 tick 이 갚는다.
        case owed
        /// 마지막 조회 뒤 월요일 0시(KST)를 넘었다 — 폴링 tick 이 한 번(1분 창을 건너뛴다).
        case weekRolled
    }

    /// 발사 판정 + 발사. 발사했으면 그 Task 를 돌려준다(테스트가 기다린다). **1분 창 안이면 요청 0건**이다.
    @discardableResult
    func refreshWeeklyWork(reason: WeeklyWorkFetchReason) -> Task<Void, Never>? {
        guard session != nil else { return nil }
        let now = clock()
        // 월요일 0시(KST)를 지난 뒤 첫 조회는 1분 창을 건너뛴다 — 창에 막히면 지난주 줄("이번 주 근무 완료 · 💎 +270 받았어요")이
        // 새 주에도 남는다(폰 `weekHasRolled` 와 같은 규칙). 경계 **뒤에** 한 번 물었으면 실패했어도 다시 창을 따른다(두드리지 않는다).
        if let last = lastWeeklyWorkFetchAt, now >= last,
           now.timeIntervalSince(last) < Self.weeklyWorkMinIntervalSeconds,
           !weeklyWorkWeekEndedSinceLastFetch(now: now) {
            // 종료 직후의 조회만 빚으로 남긴다. 나머지 박자는 1분 안에 이미 물은 값이 있으니 그대로 쓴다.
            if reason == .workEnded { weeklyWorkFetchOwed = true }
            return nil
        }
        // 스탬프는 **발사 시점**에 찍는다(지갑 sync 와 같은 규약) — 성공에만 찍으면 서버가 죽어 있는 동안 매 박자가 재시도한다.
        lastWeeklyWorkFetchAt = now
        weeklyWorkFetchOwed = false
        return Task { @MainActor [weak self] in
            await self?.performWeeklyWorkFetch()
        }
    }

    /// 폴링 tick 전용 — 빚이 있고 1분이 지났을 때, 또는 마지막 조회 뒤 주가 바뀌었을 때만 발사한다. **요청 0건이 기본값이다.**
    /// 주 넘김을 여기서도 보는 이유: 패널을 열어 둔 채 근무를 안 하는 사람에겐 다른 박자가 오지 않아, 월요일이 돼도 지난주 줄이
    /// 무한정 남는다. 경계 뒤 한 번만 나간다(발사 시점에 스탬프가 경계 뒤로 옮겨진다).
    @discardableResult
    func refreshWeeklyWorkIfOwed() -> Task<Void, Never>? {
        if weeklyWorkWeekEndedSinceLastFetch(now: clock()) { return refreshWeeklyWork(reason: .weekRolled) }
        guard weeklyWorkFetchOwed else { return nil }
        return refreshWeeklyWork(reason: .owed)
    }

    /// 화면의 주(`weeklyWork`)가 마지막 조회 **뒤에** 끝났는가 — 그 조회가 지난주에 떠났고 지금은 다음 주 월요일 0시(KST) 뒤다.
    /// 알던 값이 없거나 물은 적이 없으면 거짓(그때는 막을 창도 없다).
    func weeklyWorkWeekEndedSinceLastFetch(now: Date) -> Bool {
        guard let last = lastWeeklyWorkFetchAt, let status = weeklyWork else { return false }
        return status.weekEnded(after: last, by: now)
    }

    /// 근무가 끝난 직후. **종료 기록(큐)이 서버에 닿은 뒤에** 묻는다 — 먼저 물으면 서버는 아직 열린 세션을 지금까지로 재고,
    /// 자리 비움 마감처럼 과거 시각으로 닫는 근무는 그 차이만큼 부풀려 잰다(정산은 되돌릴 수 없다).
    func refreshWeeklyWorkAfterWorkEnded() {
        let queue = syncTask
        Task { @MainActor [weak self] in
            await queue?.value
            self?.refreshWeeklyWork(reason: .workEnded)
        }
    }

    /// 실제 왕복. 실패(네트워크 · 함수가 없는 옛 서버 · 응답 해석 실패)는 **알던 값을 지우지 않는다** — 다음 박자가 다시 묻는다.
    func performWeeklyWorkFetch() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        let rubySerial = rubyBalanceWriteSerial
        do {
            let status = try await withSessionRetry { activeSession in
                try await service.weeklyWorkStatus(accessToken: activeSession.accessToken)
            }
            guard generation == sessionGeneration else { return }
            applyWeeklyWork(status, rubyWriteSerialAtDeparture: rubySerial)
        } catch {
            // 조용히 삼킨다. 줄은 마지막으로 알던 값을 그대로 그린다(한 번도 못 받았으면 안 그린다).
        }
    }

    /// 응답 반영(순수 상태 전이 — 네트워크 없음). 테스트가 이 한 함수로 규칙을 고정한다.
    ///
    /// `rubyWriteSerialAtDeparture` = 요청이 떠날 때의 `rubyBalanceWriteSerial`. nil 이면 비교하지 않는다(직접 부르는 테스트).
    func applyWeeklyWork(_ status: WeeklyWorkStatus, rubyWriteSerialAtDeparture: Int? = nil) {
        // "새로 받은 단계"는 **덮기 전의 값**과 비교해야 한다(덮은 뒤에 비교하면 언제나 빈손이다).
        let grants = status.newlyGranted(since: weeklyWork)
        if let ruby = status.rubyBalance {
            let untouched = rubyWriteSerialAtDeparture.map { $0 == rubyBalanceWriteSerial } ?? true
            if untouched {
                let normalized = max(0, ruby)
                if rubyBalance != normalized { rubyBalance = normalized }
                // 잔량을 옮겼으면 **언제나** 상점 변이로 적는다 — 그 전에 떠난 상점 조회가 늦게 와서 지급 전 잔량으로 덮지 않게.
                // granted_now 가 있을 때만 적으면 흔한 경우(cron 이 1분 안에 먼저 줘서 granted_now 가 빈 배열)를 놓친다:
                // cron 지급 전에 100 을 읽은 상점 조회가 이 150 뒤에 도착해 100 으로 되돌렸다(검토 지적 2026-10-16).
                // 적힌 상점 조회는 버려지고 한 번 다시 읽는다(`loadShopState`) — 최악이 요청 하나 더다.
                noteShopMutation()
            } else if !grants.isEmpty {
                // 그 사이 다른 쓰기가 있어 이 값은 버렸다 — 그런데 루비가 늘었으니 사실을 다시 읽는다(옛 잔량이 화면에 남지 않게).
                loadShopState()
            }
        }
        // 줄을 그릴 만큼 모르면 **알던 값을 덮지 않는다**(한 칸 빠진 응답이 멀쩡한 줄을 지우지 않게).
        if status.isUsable, weeklyWork != status { weeklyWork = status }
        guard !grants.isEmpty else { return }
        let total = grants.reduce(0) { $0 + $1.ruby }
        missionNotice = WeeklyWorkCopy.grantNotice(grants)
        onRewardTrigger?(.rubyReward(amount: total))
    }
}
