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

/// `weekly_work_status()` 응답.
///
/// ```json
/// { "week_start": "2026-10-12", "next_week_start": "2026-10-19", "worked_seconds": 83456,
///   "tiers": [ {"hours": 20, "ruby": 20, "claimed": true}, … ],
///   "granted_now": [ {"hours": 20, "ruby": 20} ], "ruby_balance": 1057, "server_now_ms": 1781234567890 }
/// ```
///
/// ★ **이 타입의 디코드는 칸 하나 때문에 throw 하지 않는다**(최상위가 객체가 아닐 때만 throw 한다 — 그건 응답이 아니다).
package struct WeeklyWorkStatus: Decodable, Equatable, Sendable {
    /// 한 단계. `claimed` = 이 주 · 이 단계의 장부 행이 있다(= 이미 받았다).
    package struct Tier: Equatable, Sendable {
        package let hours: Int
        package let ruby: Int
        package let claimed: Bool

        package init(hours: Int, ruby: Int, claimed: Bool) {
            self.hours = hours
            self.ruby = ruby
            self.claimed = claimed
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

    package init(weekStart: String? = nil, nextWeekStart: String? = nil, workedSeconds: Int? = nil,
                 tiers: [Tier] = [], grantedNow: [Grant] = [], rubyBalance: Int? = nil, serverNowMs: Int? = nil) {
        self.weekStart = weekStart
        self.nextWeekStart = nextWeekStart
        self.workedSeconds = workedSeconds
        self.tiers = Self.normalized(tiers)
        self.grantedNow = grantedNow
        self.rubyBalance = rubyBalance
        self.serverNowMs = serverNowMs
    }

    /// 키는 서비스 디코더의 `.convertFromSnakeCase` 를 거친 **카멜**이다(`worked_seconds` → `workedSeconds`).
    package enum CodingKeys: String, CodingKey {
        case weekStart, nextWeekStart, workedSeconds, tiers, grantedNow, rubyBalance, serverNowMs
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
            serverNowMs: c.weeklyLossyInt(forKey: .serverNowMs)
        )
    }

    private static func normalized(_ tiers: [Tier]) -> [Tier] {
        var seen = Set<Int>()
        return tiers.sorted { $0.hours < $1.hours }.filter { seen.insert($0.hours).inserted }
    }

    // MARK: 파생(순수) — 맥 · 폰이 같은 답을 내게 여기 둔다

    /// 줄을 그릴 만큼 아는가: 누적초와 단계 표(한 행 이상). 하나라도 모르면 화면은 줄을 **안 그린다** —
    /// 모르는 값을 0 으로 그리면 "이번 주 0분"이라는 거짓말이 된다.
    package var isUsable: Bool { workedSeconds != nil && !tiers.isEmpty }

    /// 화면이 쓰는 누적초(음수 방어). `isUsable` 이 거짓이면 0 이지만, 그때는 줄 자체를 그리지 않는다.
    package var displayWorkedSeconds: Int { max(0, workedSeconds ?? 0) }

    /// 아직 안 받은 첫 단계(시간 오름차순). nil = 다 받았다(또는 표가 없다).
    package var nextUnclaimedTier: Tier? { tiers.first { !$0.claimed } }

    /// 세 단계를 **다** 받았는가. 빈 표는 다 받은 것이 아니다(모르는 것이다).
    package var isComplete: Bool { !tiers.isEmpty && nextUnclaimedTier == nil }

    /// 다음 단계의 문턱을 이미 넘었는데 아직 장부에 없다 — 다음 정산(cron 1분)에 들어온다. 화면은 "곧"이라고 말한다.
    package var isNextTierReached: Bool {
        guard let next = nextUnclaimedTier else { return false }
        return displayWorkedSeconds >= next.thresholdSeconds
    }

    /// 진행 바(0…1) — **다음 안 받은 단계까지**의 누적 비율. 다 받았으면 1.
    package var progressToNextTier: Double {
        guard let next = nextUnclaimedTier else { return tiers.isEmpty ? 0 : 1 }
        guard next.thresholdSeconds > 0 else { return 1 }
        return min(1, Double(displayWorkedSeconds) / Double(next.thresholdSeconds))
    }

    /// 단계 표의 루비 합(다 받으면 이만큼 — 지금 표로는 270).
    package var totalRuby: Int { tiers.reduce(0) { $0 + max(0, $1.ruby) } }

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
        if let previous, previous.weekStart != nil, previous.weekStart == weekStart {
            let wasClaimed = Dictionary(previous.tiers.map { ($0.hours, $0.claimed) }, uniquingKeysWith: { first, _ in first })
            for tier in tiers where tier.claimed && wasClaimed[tier.hours] == false {
                add(Grant(hours: tier.hours, ruby: tier.ruby))
            }
        }
        return result
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
}

// MARK: - 관대한 디코드 부품(이 파일 전용)

/// 깨진 단계 행은 nil — 목록 디코드는 그 행만 버리고 나머지를 산다.
private struct WeeklyLossyTier: Decodable {
    let tier: WeeklyWorkStatus.Tier?

    enum CodingKeys: String, CodingKey { case hours, ruby, claimed }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let hours = c.weeklyLossyInt(forKey: .hours), hours > 0,
              let ruby = c.weeklyLossyInt(forKey: .ruby)
        else {
            tier = nil
            return
        }
        // claimed 가 없거나 모양이 틀리면 **안 받은 것**으로 둔다 — 받았다고 그리면 아직 안 준 루비를 준 것처럼 말한다.
        tier = WeeklyWorkStatus.Tier(hours: hours, ruby: ruby, claimed: c.weeklyLossy(Bool.self, forKey: .claimed) ?? false)
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
