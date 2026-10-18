import Foundation

// MARK: - 주간 누적 근무 보상 (v0.3.55 맥 · 1.0.8(19) 폰)
//
// 사장님 확정(2026-10-16): 한 주 누적 근무가 20시간을 넘으면 루비 20, 40시간 50, 60시간 200 — **단계마다 따로** 준다
// (60시간이면 그 주에 270). 한 주는 KST 월요일 0시 → 다음 월요일 0시. 3시간 랩(+3)은 그대로이고 이것은 더해진 보상이다.
//
// 서버 정본은 `supabase/migrations/20261016120000_weekly_work_reward.sql` 이다. 요점만:
//   · 근무 시간은 3시간 랩과 **같은 눈금**이다(하루 단위로 자른 세션 · 신호 끊김 컷 · 열린 세션은 지금까지).
//   · 지급은 서버가 한다 — cron 이 1분마다 정산하고, `weekly_work_status()` 도 부르는 순간 먼저 정산한다.
//     (사용자 · 주 · 단계)당 한 번은 DB 유니크 인덱스가 막는다. 클라는 **보여 주기만** 한다.
//   · 단계 표(시간 · 루비)는 응답의 `tiers` 가 말한다 — 클라에 20/40/60 · 20/50/200 을 적지 않는다(값이 바뀌어도 앱을 다시 낼
//     필요가 없게 · 화면이 서버와 다른 숫자를 약속하지 않게).
//
// ── 이 파일이 지키는 것 ──
// ① **디코드가 통째로 죽지 않는다.** 키가 없거나 모양이 틀린 칸은 nil/빈 값으로, 깨진 단계 행은 그 행만 버린다. 서버와 앱이
//    한 단계 어긋난 창(앱 먼저 · db push 나중, 또는 그 반대)에서 한 칸 때문에 줄 전체가 사라지면 안 된다. 그 대가로 화면은
//    `isUsable` 로 "줄을 그릴 만큼 아는가"를 묻는다.
// ② **"방금 받았다"는 서버가 넣은 행으로만 말한다.** `granted_now`(이 호출이 넣은 행) 또는 같은 주에서 `claimed` 가
//    거짓 → 참으로 바뀐 단계(cron 이 먼저 넣은 행)뿐이다 — 클라가 시간을 재서 "넘었다"고 판단하지 않는다.
// ③ **v0.3.58 — 받기 버튼으로 받는다**(사장님 2026-10-19: "기존의 주간 목표시간 달성하는것도 받는 버튼으로 받게 바꿔주고").
//    서버 `20261019121000_weekly_claim.sql` 부터 정산은 **달성 기록만** 하고 루비는 `weekly_work_claim()` 이 줄 때 움직인다.
//    응답엔 단계마다 `achieved` · `claimable`, 위에 `pending`(어느 주든 받을 것 전부) · `claimable_ruby` 가 더해지고
//    `granted_now` 는 언제나 `[]` 다. 옛 칸(`tiers[].claimed` · `granted_now`)의 뜻은 그대로라 0.3.55~0.3.57 이 계속 읽는다.
//    새 칸이 **없는** 응답(옛 서버)은 예전 그대로다 — 버튼이 없고 ②로 알린다(`supportsClaim`).

/// `weekly_work_status()` 응답.
///
/// ```json
/// { "week_start": "2026-10-12", "next_week_start": "2026-10-19", "worked_seconds": 83456,
///   "tiers": [ {"hours": 20, "ruby": 20, "claimed": true}, … ],
///   "granted_now": [ {"hours": 20, "ruby": 20} ], "ruby_balance": 1057, "server_now_ms": 1781234567890 }
/// ```
///
/// v0.3.58 받기 서버는 더 싣는다(없으면 nil — 옛 서버):
/// ```json
/// { …, "tiers": [ {"hours": 20, "ruby": 20, "claimed": false, "achieved": true, "claimable": true}, … ],
///   "granted_now": [], "pending": [ {"week_start": "2026-10-12", "hours": 20, "ruby": 20} ], "claimable_ruby": 20,
///   "claimed_now": [ {"week_start": "2026-10-12", "hours": 20, "ruby": 20} ] }   // claimed_now 는 weekly_work_claim 응답만
/// ```
///
/// ★ **이 타입의 디코드는 칸 하나 때문에 throw 하지 않는다**(최상위가 객체가 아닐 때만 throw 한다 — 그건 응답이 아니다).
package struct WeeklyWorkStatus: Decodable, Equatable, Sendable {
    /// 한 단계. `claimed` = 이 주 · 이 단계의 장부 행이 있다(= 이미 받았다).
    package struct Tier: Equatable, Sendable {
        package let hours: Int
        package let ruby: Int
        package let claimed: Bool
        /// v0.3.58 받기 서버: 이 주 · 이 단계를 채웠다(달성 행이 있다). nil = 옛 서버(모른다).
        package let achieved: Bool?
        /// v0.3.58 받기 서버: 채웠고 아직 안 받았다. nil = 옛 서버.
        package let claimable: Bool?

        package init(hours: Int, ruby: Int, claimed: Bool, achieved: Bool? = nil, claimable: Bool? = nil) {
            self.hours = hours
            self.ruby = ruby
            self.claimed = claimed
            self.achieved = achieved
            self.claimable = claimable
        }

        /// 이 단계의 문턱(초).
        package var thresholdSeconds: Int { hours * 3_600 }
    }

    /// 이번 호출(또는 같은 주 안에서 지난 조회 뒤)에 들어온 지급 한 건. `weekStart` 가 nil 이면 **이번 주**다 —
    /// 서버는 지난주 소급분에만 `week_start` 를 싣는다(일요일 23:59 에 넘긴 단계를 월요일에 정산한 것).
    package struct Grant: Equatable, Sendable {
        package let hours: Int
        package let ruby: Int
        package let weekStart: String?

        package init(hours: Int, ruby: Int, weekStart: String? = nil) {
            self.hours = hours
            self.ruby = ruby
            self.weekStart = weekStart
        }
    }

    /// v0.3.58 — 채웠고 아직 안 받은 단계 하나(**어느 주든** — 지난주에 채우고 안 받은 것도 남는다. 달성은 사라지지 않는다).
    package struct Pending: Equatable, Sendable {
        /// `YYYY-MM-DD`(그 주 월요일). 비어 있을 수 있다(서버가 안 실었다 — 받기는 어차피 전부 받기다).
        package let weekStart: String
        package let hours: Int
        package let ruby: Int

        package init(weekStart: String, hours: Int, ruby: Int) {
            self.weekStart = weekStart
            self.hours = hours
            self.ruby = max(0, ruby)
        }
    }

    /// `YYYY-MM-DD`(KST 월요일). 서버가 판정한 이번 주.
    package var weekStart: String?
    package var nextWeekStart: String?
    /// 이번 주 누적 근무초(월요일 0시부터 지금까지 · 열린 세션 포함). **nil = 모른다**(0 이 아니다).
    package var workedSeconds: Int?
    /// 단계 표 — **시간 오름차순으로 정렬해 둔다**(서버 순서에 기대지 않는다 · 같은 시간이 둘이면 앞의 것만).
    package var tiers: [Tier]
    /// 이 호출이 장부에 **실제로 넣은** 행.
    package var grantedNow: [Grant]
    /// 정산 뒤 루비 잔량. nil = 안 알려 줬다(스토어는 nil 이면 잔량을 건드리지 않는다).
    package var rubyBalance: Int?
    /// 서버 시각(epoch 밀리초). 진단용.
    package var serverNowMs: Int?
    /// v0.3.58 — 받을 것 전부(어느 주든). **nil = 옛 서버**(이 칸이 없다 → 버튼 없음 · 예전 알림). 빈 배열 = 받을 것이 없다.
    package var pending: [Pending]?
    /// v0.3.58 — 받을 루비 합(`pending` 의 합). nil = 옛 서버.
    package var claimableRuby: Int?
    /// v0.3.58 — `weekly_work_claim` 이 이 호출에 **실제로 넣은** 지급. 상태 조회는 언제나 비어 있다.
    package var claimedNow: [Grant]

    package init(weekStart: String? = nil, nextWeekStart: String? = nil, workedSeconds: Int? = nil,
                 tiers: [Tier] = [], grantedNow: [Grant] = [], rubyBalance: Int? = nil, serverNowMs: Int? = nil,
                 pending: [Pending]? = nil, claimableRuby: Int? = nil, claimedNow: [Grant] = []) {
        self.weekStart = weekStart
        self.nextWeekStart = nextWeekStart
        self.workedSeconds = workedSeconds
        self.tiers = Self.normalized(tiers)
        self.grantedNow = grantedNow
        self.rubyBalance = rubyBalance
        self.serverNowMs = serverNowMs
        self.pending = pending
        self.claimableRuby = claimableRuby.map { max(0, $0) }
        self.claimedNow = claimedNow
    }

    /// 키는 서비스 디코더의 `.convertFromSnakeCase` 를 거친 **카멜**이다(`worked_seconds` → `workedSeconds`).
    package enum CodingKeys: String, CodingKey {
        case weekStart, nextWeekStart, workedSeconds, tiers, grantedNow, rubyBalance, serverNowMs
        case pending, claimableRuby, claimedNow
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            weekStart: c.weeklyLossy(String.self, forKey: .weekStart),
            nextWeekStart: c.weeklyLossy(String.self, forKey: .nextWeekStart),
            workedSeconds: c.weeklyLossyInt(forKey: .workedSeconds),
            tiers: (c.weeklyLossyList(WeeklyLossyTier.self, forKey: .tiers) ?? []).compactMap(\.tier),
            grantedNow: (c.weeklyLossyList(WeeklyLossyGrant.self, forKey: .grantedNow) ?? []).compactMap(\.grant),
            rubyBalance: c.weeklyLossyInt(forKey: .rubyBalance),
            serverNowMs: c.weeklyLossyInt(forKey: .serverNowMs),
            // 칸이 **있을 때만** 배열이다(없으면 nil = 옛 서버). 모양이 틀린 배열 원소는 그 원소만 버린다.
            pending: c.weeklyLossyList(WeeklyLossyPending.self, forKey: .pending)?.compactMap(\.pending),
            claimableRuby: c.weeklyLossyInt(forKey: .claimableRuby),
            claimedNow: (c.weeklyLossyList(WeeklyLossyGrant.self, forKey: .claimedNow) ?? []).compactMap(\.grant)
        )
    }

    fileprivate static func normalized(_ tiers: [Tier]) -> [Tier] {
        var seen = Set<Int>()
        return tiers.sorted { $0.hours < $1.hours }.filter { seen.insert($0.hours).inserted }
    }

    // MARK: 파생(순수) — 맥 · 폰이 같은 답을 내게 여기 둔다

    /// 줄을 그릴 만큼 아는가: 누적초와 단계 표(한 행 이상). 하나라도 모르면 화면은 줄을 **안 그린다** —
    /// 모르는 값을 0 으로 그리면 "이번 주 0분"이라는 거짓말이 된다.
    package var isUsable: Bool { workedSeconds != nil && !tiers.isEmpty }

    /// 화면이 쓰는 누적초(음수 방어). `isUsable` 이 거짓이면 0 이지만, 그때는 줄 자체를 그리지 않는다.
    package var displayWorkedSeconds: Int { max(0, workedSeconds ?? 0) }

    /// 단계 표의 루비 합(다 받으면 이만큼 — 지금 표로는 270).
    package var totalRuby: Int { tiers.reduce(0) { $0 + max(0, $1.ruby) } }

    // MARK: v0.3.58 받기(순수)

    /// 이 응답이 받기 서버의 것인가 — `pending` 이나 `claimable_ruby` 가 실려 왔다. 거짓(옛 서버)이면 버튼도 받을 것도 없다.
    package var supportsClaim: Bool { pending != nil || claimableRuby != nil }

    /// 받을 루비(어느 주든). 서버 합(`claimable_ruby`)이 있으면 그 값, 없으면 `pending` 의 합. 옛 서버는 0.
    package var pendingRuby: Int {
        guard supportsClaim else { return 0 }
        return max(0, claimableRuby ?? (pending ?? []).reduce(0) { $0 + $1.ruby })
    }

    /// 받을 단계 수(레일 배지에 더해진다). `pending` 이 없는데 합만 양수면 1(한 번 누르면 받을 것이 있다는 사실은 말한다).
    package var pendingCount: Int {
        guard pendingRuby > 0 else { return 0 }
        return max(1, pending?.count ?? 1)
    }

    /// [받기 +N] 버튼을 세우는가.
    package var hasClaimable: Bool { pendingRuby > 0 }

    /// 이 호출(받기)이 넣은 지급의 루비 합.
    package var claimedNowRuby: Int { claimedNow.reduce(0) { $0 + max(0, $1.ruby) } }

    /// 다음 주 월요일 0시(KST) — 이 응답의 주가 끝나는 순간. 못 읽으면 nil.
    package var nextWeekStartDate: Date? { WeeklyWorkCalendar.kstMidnight(nextWeekStart) }

    /// 이 응답의 주가 `now` 에 끝났는가(다음 주 월요일 0시 이후). 끝났으면 화면 값은 지난주 것이다.
    package func hasEnded(at now: Date) -> Bool {
        guard let end = nextWeekStartDate else { return false }
        return now >= end
    }

    /// 주 경계(다음 주 월요일 0시)가 `last`(이 값을 물은 때) 뒤 · `now` 이전에 있었는가 — 맥 1분 창을 건너뛰는 조건.
    /// 경계 **뒤에** 물었으면(그 조회가 실패해 이 값이 아직 지난주여도) 거짓이다 — 실패한 서버를 매 박자 두드리지 않는다.
    package func weekEnded(after last: Date, by now: Date) -> Bool {
        guard let end = nextWeekStartDate else { return false }
        return last < end && end <= now
    }

    /// 화면의 게이지(맥 줄 · 폰 카드가 같은 값을 그린다). 줄을 그릴 만큼 모르면 nil.
    package var gauge: WeeklyWorkGauge? {
        guard isUsable else { return nil }
        return WeeklyWorkGauge.make(workedSeconds: displayWorkedSeconds, tiers: tiers)
    }

    /// `previous`(같은 사람의 지난 조회) 다음에 **새로 들어온** 지급. 두 갈래의 합집합이다:
    ///  ① `granted_now` — 이 호출이 넣은 행(지난주 소급분 포함).
    ///  ② 같은 주에서 `claimed` 가 거짓 → 참으로 바뀐 단계 — cron 이 1분마다 먼저 정산하므로 앱이 5분마다 묻는 사이
    ///     넘긴 단계는 거의 언제나 이 갈래로 온다(① 만 보면 알림이 사실상 영영 안 뜬다).
    /// 같은 (주, 단계)는 한 번만 센다. `previous` 가 nil(실행 뒤 첫 조회)이거나 주가 바뀌었으면 ② 는 없다 — 그때 이미
    /// 참인 단계가 "방금"인지 "어제"인지 알 수 없고, 모르는 것을 방금이라고 말하지 않는다.
    package func newlyGranted(since previous: WeeklyWorkStatus?) -> [Grant] {
        var result: [Grant] = []
        var seen = Set<String>()
        func add(_ grant: Grant) {
            let week = grant.weekStart ?? weekStart ?? ""
            guard grant.ruby > 0, seen.insert("\(week)|\(grant.hours)").inserted else { return }
            result.append(grant)
        }
        for grant in grantedNow {
            // 이번 주 행은 weekStart 를 비워 둔다(서버가 이번 주 행에 week_start 를 실어 보내도 같은 뜻으로 접는다).
            let isThisWeek = grant.weekStart == nil || grant.weekStart == weekStart
            add(Grant(hours: grant.hours, ruby: grant.ruby, weekStart: isThisWeek ? nil : grant.weekStart))
        }
        // v0.3.58 받기 서버에서는 ② 를 보지 않는다 — `claimed` 가 거짓 → 참이 되는 길은 이제 **사람이 [받기]를 누른 것**뿐이고
        // (이 맥이면 받기 연출이 말하고, 폰이면 폰에서 이미 봤다), 그걸 "N시간 채웠어요"로 또 말하면 같은 일을 두 번 알린다.
        if !supportsClaim, let previous, previous.weekStart != nil, previous.weekStart == weekStart {
            let wasClaimed = Dictionary(previous.tiers.map { ($0.hours, $0.claimed) }, uniquingKeysWith: { first, _ in first })
            for tier in tiers where tier.claimed && wasClaimed[tier.hours] == false {
                add(Grant(hours: tier.hours, ruby: tier.ruby))
            }
        }
        return result
    }
}

// MARK: - 주 달력(KST) — 맥 · 폰이 같은 "월요일 0시"를 쓴다

package enum WeeklyWorkCalendar {
    /// "2026-10-19" → 그 날 0시(KST). 못 읽으면 nil.
    package static func kstMidnight(_ day: String?) -> Date? {
        guard let day else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return kst.date(from: components)
    }

    package static let kst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()
}

// MARK: - 게이지(지금 퀘스트 하나) — 사장님 늦은 변경(2026-10-16 12:4x)
//
// "맨처음엔 20시간 달성 기준이고 20시간 달성하고 40시간 달성하러가는사람이면 그거 기준으로 게이지 뜨고, 40시간 달성하고 60시간
//  달성하러가는사람은 60시간 기준으로 뜨게끔. 그리고 60시간 넘으면 완료로 화면 처리하고."
//
//  · 지금 퀘스트 = 누적초가 **아직 못 넘은** 첫 단계(시간 오름차순). `claimed` 로 고르지 않는다 — 지급은 cron 을 최대 1분 늦게
//    따라오므로, claimed 로 고르면 20시간을 막 넘긴 사람에게 1분 동안 "20시간 달성하기"가 남는다.
//  · 채움 = 누적초 ÷ (퀘스트 시간 × 3600) — **이번 주 누적**이다(구간이 아니다): 20시간이면 40시간 게이지가 이미 절반,
//    45시간이면 60시간 게이지가 75%. 0…1 로 자른다.
//  · 마지막 단계를 넘으면 완료 — 게이지는 가득, 다음 목표는 없다. 받은 합은 **장부(`claimed`)가 말하는 만큼만**이다
//    (cron 이 아직이면 270 이 아니라 70 — 안 준 루비를 받았다고 말하지 않는다).

/// 맥 줄 · 폰 카드가 그리는 게이지 하나. 만드는 곳은 `make(workedSeconds:tiers:)` 하나다.
package struct WeeklyWorkGauge: Equatable, Sendable {
    /// 지금 퀘스트의 시간(20 · 40 · 60). 완료면 마지막 단계의 시간.
    package let questHours: Int
    /// 0…1 — 이번 주 누적 ÷ 퀘스트 시간. 완료면 1.
    package let fill: Double
    /// 마지막 단계의 시간을 넘었다(누적초로 판정).
    package let isComplete: Bool
    /// 지금 퀘스트를 채우면 받는 루비. 완료면 마지막 단계의 루비(화면은 완료일 때 이 값을 쓰지 않는다).
    package let reward: Int
    /// 장부에 들어간(= `claimed`) 단계의 루비 합. 완료 화면의 "💎 +N 받았어요"는 이 값만 말한다.
    package let claimedTotal: Int

    package init(questHours: Int, fill: Double, isComplete: Bool, reward: Int, claimedTotal: Int) {
        self.questHours = questHours
        self.fill = fill
        self.isComplete = isComplete
        self.reward = reward
        self.claimedTotal = claimedTotal
    }

    /// 표가 비면 nil(모르는 것을 0 으로 그리지 않는다). 표 순서 · 중복은 여기서 다시 정리한다(직접 만든 표도 같은 답).
    package static func make(workedSeconds: Int, tiers: [WeeklyWorkStatus.Tier]) -> WeeklyWorkGauge? {
        let table = WeeklyWorkStatus.normalized(tiers.filter { $0.hours > 0 })
        guard let last = table.last else { return nil }
        let worked = max(0, workedSeconds)
        let claimedTotal = table.reduce(0) { $0 + ($1.claimed ? max(0, $1.ruby) : 0) }
        guard let quest = table.first(where: { worked < $0.thresholdSeconds }) else {
            return WeeklyWorkGauge(questHours: last.hours, fill: 1, isComplete: true,
                                   reward: max(0, last.ruby), claimedTotal: claimedTotal)
        }
        let fill = min(1, max(0, Double(worked) / Double(quest.thresholdSeconds)))
        return WeeklyWorkGauge(questHours: quest.hours, fill: fill, isComplete: false,
                               reward: max(0, quest.ruby), claimedTotal: claimedTotal)
    }

    /// 이미 넘긴 단계인가(게이지 옆의 작은 표시 — 받았으면 체크, 장부가 아직이면 흐리게). 완료면 전부.
    package func hasPassed(_ tier: WeeklyWorkStatus.Tier) -> Bool {
        isComplete || tier.hours < questHours
    }
}

// MARK: - 서비스

extension SupabaseWorkService {
    package nonisolated static let weeklyWorkStatusPath = "/rest/v1/rpc/weekly_work_status"

    /// 이번 주 누적 근무 보상 상태. `weekly_work_status()` — 인자 없음(서버가 `auth.uid()` 를 쓴다).
    ///
    /// **읽기 전용이 아니다**: 서버가 이 사람의 이번 주 · 지난주를 **먼저 정산**하고(넘긴 단계를 지급) 그 결과를 돌려준다.
    /// 그래도 폰에서 불러도 된다 — 본인 계정에만 작용하고 (사용자 · 주 · 단계)당 한 번은 DB 가 막는다(cron 이 어차피
    /// 1분마다 같은 정산을 한다). 그래서 맥 전용 조각(`SupabaseWorkServiceMacOnly.swift`)이 아니라 여기 둔다.
    ///
    /// 함수가 없는 서버(PGRST202 — db push 전 창)는 `.databaseSchemaMissing` 으로 throw 한다. 옛 모양이 없으므로 되묻지 않고,
    /// 호출부(스토어)는 실패를 삼켜 줄을 안 그린다.
    package func weeklyWorkStatus(accessToken: String) async throws -> WeeklyWorkStatus {
        let data = try await send(
            path: Self.weeklyWorkStatusPath,
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(WeeklyWorkStatus.self, from: data)
    }

    package nonisolated static let weeklyWorkClaimPath = "/rest/v1/rpc/weekly_work_claim"

    /// v0.3.58 받기. `weekly_work_claim(p_week_start, p_hours)` — 둘 다 nil 이면 **받을 것 전부(어느 주든)**. 서버가 먼저 정산하므로
    /// 방금 넘긴 단계도 한 번에 받는다. 응답은 `weekly_work_status()` 와 같은 모양 + `claimed_now`. 장부 사유는 0.3.55 와 **같은 꼴**
    /// (`mission:week:<주>:<h>h`)이라 기존 유니크 인덱스가 옛 자동 지급 · 새 받기 사이의 두 번 지급을 막는다.
    package func weeklyWorkClaim(accessToken: String, weekStart: String? = nil, hours: Int? = nil) async throws -> WeeklyWorkStatus {
        let data = try await send(
            path: Self.weeklyWorkClaimPath,
            method: "POST",
            body: WeeklyWorkClaimRequest(weekStart: weekStart, hours: hours),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(WeeklyWorkStatus.self, from: data)
    }
}

/// `weekly_work_claim(p_week_start, p_hours)` 본문. **키 둘을 언제나 싣는다**(nil 은 JSON null) — 키 집합이 흔들리면 PostgREST 가 다른
/// 함수를 찾는다(`GachaPullRequest` 와 같은 규약). 인코더가 `.convertToSnakeCase` 라 `pWeekStart` → `p_week_start`.
package struct WeeklyWorkClaimRequest: Encodable, Equatable, Sendable {
    package let pWeekStart: String?
    package let pHours: Int?

    package init(weekStart: String?, hours: Int?) {
        pWeekStart = weekStart
        pHours = hours
    }

    private enum CodingKeys: String, CodingKey { case pWeekStart, pHours }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let pWeekStart { try c.encode(pWeekStart, forKey: .pWeekStart) } else { try c.encodeNil(forKey: .pWeekStart) }
        if let pHours { try c.encode(pHours, forKey: .pHours) } else { try c.encodeNil(forKey: .pHours) }
    }
}

// MARK: - 관대한 디코드 부품(이 파일 전용)

/// 깨진 단계 행은 nil — 목록 디코드는 그 행만 버리고 나머지를 산다.
private struct WeeklyLossyTier: Decodable {
    let tier: WeeklyWorkStatus.Tier?

    enum CodingKeys: String, CodingKey { case hours, ruby, claimed, achieved, claimable }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let hours = c.weeklyLossyInt(forKey: .hours), hours > 0,
              let ruby = c.weeklyLossyInt(forKey: .ruby)
        else {
            tier = nil
            return
        }
        // claimed 가 없거나 모양이 틀리면 **안 받은 것**으로 둔다 — 받았다고 그리면 아직 안 준 루비를 준 것처럼 말한다.
        tier = WeeklyWorkStatus.Tier(hours: hours, ruby: ruby, claimed: c.weeklyLossy(Bool.self, forKey: .claimed) ?? false,
                                     achieved: c.weeklyLossy(Bool.self, forKey: .achieved),
                                     claimable: c.weeklyLossy(Bool.self, forKey: .claimable))
    }
}

/// 받을 단계 한 행(v0.3.58). 시간 · 루비가 없으면 그 행만 버린다.
private struct WeeklyLossyPending: Decodable {
    let pending: WeeklyWorkStatus.Pending?

    enum CodingKeys: String, CodingKey { case weekStart, hours, ruby }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let hours = c.weeklyLossyInt(forKey: .hours), hours > 0,
              let ruby = c.weeklyLossyInt(forKey: .ruby)
        else {
            pending = nil
            return
        }
        pending = WeeklyWorkStatus.Pending(weekStart: c.weeklyLossy(String.self, forKey: .weekStart) ?? "", hours: hours, ruby: ruby)
    }
}

private struct WeeklyLossyGrant: Decodable {
    let grant: WeeklyWorkStatus.Grant?

    enum CodingKeys: String, CodingKey { case hours, ruby, weekStart }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let hours = c.weeklyLossyInt(forKey: .hours),
              let ruby = c.weeklyLossyInt(forKey: .ruby)
        else {
            grant = nil
            return
        }
        grant = WeeklyWorkStatus.Grant(hours: hours, ruby: ruby, weekStart: c.weeklyLossy(String.self, forKey: .weekStart))
    }
}

/// 숫자면 정수로(소수는 버림) — `extract(epoch …)` 를 정수로 안 자른 서버가 `83456.5` 를 보내도 줄이 산다.
private struct WeeklyLossyNumber: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let int = try? c.decode(Int.self) {
            value = int
        } else if let double = try? c.decode(Double.self), double.isFinite, abs(double) < 9.0e15 {
            value = Int(double)
        } else {
            value = nil
        }
    }
}

/// 어떤 값이든 받아 버리는 자리(목록에서 깨진 원소를 건너뛸 때 커서를 한 칸 옮기는 용도).
private struct WeeklyDiscard: Decodable {
    init(from decoder: Decoder) throws {}
}

private extension KeyedDecodingContainer {
    /// 키가 없거나 · null 이거나 · 모양이 틀리면 nil. **throw 하지 않는다.**
    func weeklyLossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    func weeklyLossyInt(forKey key: Key) -> Int? {
        weeklyLossy(WeeklyLossyNumber.self, forKey: key)?.value
    }

    /// 배열이 아니면 nil, 배열이면 원소마다 따로 읽는다(원소 하나가 깨져도 나머지는 산다).
    func weeklyLossyList<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard contains(key), var list = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var items: [T] = []
        while !list.isAtEnd {
            if let item = try? list.decode(T.self) {
                items.append(item)
            } else if (try? list.decode(WeeklyDiscard.self)) == nil {
                break
            }
        }
        return items
    }
}
