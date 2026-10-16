import CheckCore
import Foundation

// 이번 주 누적 근무 보상(v0.3.55 · 폰 1.0.8(19) — 서버 20261016120000_weekly_work_reward.sql).
//
// 사장님 결정(2026-10-16): 한 주(월요일 0시 → 다음 월요일 0시, KST)에 누적 20시간을 넘으면 💎20, 40시간 💎50, 60시간 💎200 —
// 칸마다 **따로** 준다(60시간이면 그 주 270). 3시간 랩(+3)은 그대로 있고 이건 더해진 것이다.
//
// 폰이 하는 일은 **읽기 하나**다: `weekly_work_status()` 가 이 사용자의 지급을 먼저 정산하고(서버 한 트랜잭션 · 칸마다 한 번은
// DB 유니크 인덱스가 막는다) 이번 주 상태를 돌려준다. 근무 시간 계산 · 칸 판정 · 지급은 전부 서버 몫이고 폰은 숫자를 옮겨 적는다
// (서버 cron 도 1분마다 같은 정산을 돈다 — 앱이 꺼져 있어도 받는다).

/// `weekly_work_status()` 응답.
///
/// ★ **임시 사본**이다. 같은 응답의 모델·디코더는 맥 갈래(`v0355-weekly-mac`)가 CheckCore 에 만든다 — 두 갈래가 동시에 지어져서
///   폰 갈래는 여기 사본을 두고, 병합 단계가 이 타입을 코어 모델로 접는다(이름 `WeeklyWorkStatusDTO` 를 찾아 바꾸면 된다).
///
/// 디코드는 **삼킨다**: 칸이 없거나 · null 이거나 · 모양이 틀려도 응답 전체를 버리지 않는다(옛 서버 · 새 서버 칸 어긋남).
/// 칸 목록에서 깨진 원소 하나는 그 원소만 빠진다. 숫자는 정수 · 실수(`numeric` 이 소수로 올 때) 둘 다 받는다.
package struct WeeklyWorkStatusDTO: Decodable, Equatable, Sendable {
    /// 보상 칸 하나(서버 `weekly_work_tiers()` 의 한 행 + 이번 주에 받았는가).
    package struct Tier: Decodable, Equatable, Sendable {
        package var hours: Int
        package var ruby: Int
        /// 이번 주 이 칸의 장부 행이 있다. 모르면(칸 없음) false — 받았다고 지어내지 않는다.
        package var claimed: Bool

        package init(hours: Int, ruby: Int, claimed: Bool) {
            self.hours = hours
            self.ruby = ruby
            self.claimed = claimed
        }

        enum CodingKeys: String, CodingKey { case hours, ruby, claimed }

        package init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // 시간·루비가 없는 칸은 칸이 아니다 — 이 원소만 버린다(`WeeklyWorkLossyElement`).
            guard let hours = container.weeklyLossyInt(forKey: .hours), hours > 0,
                  let ruby = container.weeklyLossyInt(forKey: .ruby), ruby >= 0
            else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "칸에 hours·ruby 가 없다"))
            }
            self.hours = hours
            self.ruby = ruby
            claimed = container.weeklyLossy(Bool.self, forKey: .claimed) ?? false
        }
    }

    /// 이 호출이 새로 넣은 장부 행 하나. `weekStart` 는 지난주 따라잡기 지급에만 붙는다(nil = 이번 주).
    package struct Grant: Decodable, Equatable, Sendable {
        package var hours: Int
        package var ruby: Int
        package var weekStart: String?

        package init(hours: Int, ruby: Int, weekStart: String? = nil) {
            self.hours = hours
            self.ruby = ruby
            self.weekStart = weekStart
        }

        enum CodingKeys: String, CodingKey { case hours, ruby, weekStart }

        package init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let hours = container.weeklyLossyInt(forKey: .hours), hours > 0,
                  let ruby = container.weeklyLossyInt(forKey: .ruby), ruby >= 0
            else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "지급에 hours·ruby 가 없다"))
            }
            self.hours = hours
            self.ruby = ruby
            weekStart = container.weeklyLossy(String.self, forKey: .weekStart)
        }
    }

    /// 이번 주 월요일(KST, "2026-10-12"). 모르면 nil.
    package var weekStart: String?
    /// 다음 주 월요일(KST, "2026-10-19") — 이 날 0시가 되면 이 값은 지난주 것이다.
    package var nextWeekStart: String?
    /// 이번 주 누적 근무 초(서버가 3시간 랩과 **같은 잣대**로 잰다 — 열린 근무는 서버 지금까지).
    package var workedSeconds: Int
    package var tiers: [Tier]
    package var grantedNow: [Grant]
    /// 정산 뒤 루비 잔량(서버 값). 클라가 스스로 더하지 않는다.
    package var rubyBalance: Int?
    package var serverNowMs: Int64?

    package init(weekStart: String?, nextWeekStart: String?, workedSeconds: Int, tiers: [Tier], grantedNow: [Grant] = [],
                 rubyBalance: Int? = nil, serverNowMs: Int64? = nil) {
        self.weekStart = weekStart
        self.nextWeekStart = nextWeekStart
        self.workedSeconds = workedSeconds
        self.tiers = tiers
        self.grantedNow = grantedNow
        self.rubyBalance = rubyBalance
        self.serverNowMs = serverNowMs
    }

    enum CodingKeys: String, CodingKey {
        case weekStart, nextWeekStart, workedSeconds, tiers, grantedNow, rubyBalance, serverNowMs
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = container.weeklyLossy(String.self, forKey: .weekStart)
        nextWeekStart = container.weeklyLossy(String.self, forKey: .nextWeekStart)
        workedSeconds = max(0, container.weeklyLossyInt(forKey: .workedSeconds) ?? 0)
        tiers = (container.weeklyLossy([WeeklyWorkLossyElement<Tier>].self, forKey: .tiers) ?? []).compactMap(\.value)
        grantedNow = (container.weeklyLossy([WeeklyWorkLossyElement<Grant>].self, forKey: .grantedNow) ?? []).compactMap(\.value)
        rubyBalance = container.weeklyLossyInt(forKey: .rubyBalance)
        serverNowMs = container.weeklyLossyInt64(forKey: .serverNowMs)
    }
}

/// 깨진 원소 하나를 nil 로 접는 상자(배열 전체가 죽지 않게).
private struct WeeklyWorkLossyElement<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    /// 키가 없거나 · null 이거나 · 모양이 틀리면 nil. **throw 하지 않는다.**
    func weeklyLossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// 정수 또는 실수(내림). 서버 `numeric` 이 "83456.5" 같은 소수로 와도 칸을 잃지 않는다.
    func weeklyLossyInt(forKey key: Key) -> Int? {
        if let value = weeklyLossy(Int.self, forKey: key) { return value }
        guard let value = weeklyLossy(Double.self, forKey: key), value.isFinite,
              value > Double(Int.min), value < Double(Int.max) else { return nil }
        return Int(value.rounded(.down))
    }

    func weeklyLossyInt64(forKey key: Key) -> Int64? {
        if let value = weeklyLossy(Int64.self, forKey: key) { return value }
        guard let value = weeklyLossy(Double.self, forKey: key), value.isFinite,
              value > Double(Int64.min), value < Double(Int64.max) else { return nil }
        return Int64(value.rounded(.down))
    }
}

// MARK: - 서비스

/// 본문 `{}`(인자 없음 — PostgREST 는 본문의 키 집합으로 함수를 고른다).
struct WeeklyWorkStatusRequest: Encodable {}

extension SupabaseWorkService {
    package nonisolated static let weeklyWorkStatusPath = "/rest/v1/rpc/weekly_work_status"

    /// 이번 주 근무 보상 상태. `weekly_work_status()` — 인자 없음(본문 `{}`), `auth.uid()` 의 지급을 먼저 정산하고 돌려준다.
    /// 함수가 없는 서버(PGRST202 · 404)는 throw 하고 스토어가 카드를 접는다(`MobileDeviceRPC.isMissingFunction`).
    package func fetchWeeklyWorkStatus(accessToken: String) async throws -> WeeklyWorkStatusDTO {
        let data = try await send(
            path: Self.weeklyWorkStatusPath,
            method: "POST",
            body: WeeklyWorkStatusRequest(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(WeeklyWorkStatusDTO.self, from: data)
    }
}

// MARK: - 순수 규칙(화면이 읽는 값 — 맥 `swift test` 가 값으로 잰다)

/// 한 번의 '받았어요' 알림(+N). 여러 칸이 한꺼번에 들어오면 합쳐서 한 번.
package struct WeeklyWorkGrantNotice: Equatable, Sendable {
    package var ruby: Int
    /// 들어온 칸들(시간 · 오름차순). 지난주 따라잡기 지급도 섞일 수 있다.
    package var hours: [Int]

    package init(ruby: Int, hours: [Int]) {
        self.ruby = ruby
        self.hours = hours
    }
}

/// 이 기기가 마지막으로 **본** 이번 주 받은 칸(계정별 저장 — `WeeklyWorkRules.newGrants`).
package struct WeeklyWorkSeen: Equatable, Sendable {
    package var weekStart: String
    package var claimedHours: Set<Int>

    package init(weekStart: String, claimedHours: Set<Int>) {
        self.weekStart = weekStart
        self.claimedHours = claimedHours
    }

    /// 저장 글자 "2026-10-12|20,40"(빈 칸이면 "2026-10-12|").
    package var encoded: String {
        "\(weekStart)|" + claimedHours.sorted().map(String.init).joined(separator: ",")
    }

    package init?(encoded: String?) {
        guard let encoded else { return nil }
        let parts = encoded.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        weekStart = String(parts[0])
        claimedHours = Set(parts[1].split(separator: ",").compactMap { Int($0) })
    }
}

package enum WeeklyWorkRules {
    /// 칸(시간 오름차순 · 같은 시간은 처음 것만). 서버 순서를 믿지 않는다.
    package static func sortedTiers(_ status: WeeklyWorkStatusDTO) -> [WeeklyWorkStatusDTO.Tier] {
        var seen = Set<Int>()
        return status.tiers.sorted { $0.hours < $1.hours }.filter { seen.insert($0.hours).inserted }
    }

    /// 다음에 받을 칸: 아직 안 받은 칸 중 가장 낮은 것. 다 받았으면 nil.
    package static func nextTier(_ status: WeeklyWorkStatusDTO) -> WeeklyWorkStatusDTO.Tier? {
        sortedTiers(status).first { !$0.claimed }
    }

    /// 세 칸을 다 받았다(칸을 하나도 모르면 아니다).
    package static func allClaimed(_ status: WeeklyWorkStatusDTO) -> Bool {
        let tiers = sortedTiers(status)
        return !tiers.isEmpty && tiers.allSatisfy(\.claimed)
    }

    /// 이번 주 전부(💎270 — 서버 칸의 합. 값을 박지 않는다).
    package static func totalRuby(_ status: WeeklyWorkStatusDTO) -> Int {
        sortedTiers(status).reduce(0) { $0 + $1.ruby }
    }

    /// 막대: 0 → 다음 칸 시간까지의 몫(0…1). 다 받았으면 1. 칸을 모르면 0.
    ///
    /// 칸 사이(20→40)가 아니라 0 에서 재는 까닭: 숫자 줄("23시간 12분")과 막대가 같은 원점을 써야 "40시간 되면"의 거리가 읽힌다 —
    /// 칸 사이로 재면 20시간을 넘는 순간 막대가 0 으로 꺼져 '줄었다'로 읽힌다.
    package static func progress(_ status: WeeklyWorkStatusDTO) -> Double {
        if allClaimed(status) { return 1 }
        guard let next = nextTier(status) else { return 0 }
        let goal = Double(next.hours * 3600)
        guard goal > 0 else { return 0 }
        return min(1, max(0, Double(status.workedSeconds) / goal))
    }

    /// 다음 칸 시간을 이미 넘었는데 아직 장부에 없다(서버 정산이 1분 안에 돈다 — "곧 들어와요").
    package static func isNextTierPending(_ status: WeeklyWorkStatusDTO) -> Bool {
        guard let next = nextTier(status) else { return false }
        return status.workedSeconds >= next.hours * 3600
    }

    /// '받았어요' 알림에 올릴 지급.
    ///
    /// 서버의 `granted_now` 만 보면 이 알림은 **거의 영영 안 뜬다**: cron 이 1분마다 같은 정산을 돌아 칸을 넘긴 지 1분 안에 먼저
    /// 지급하므로, 앱이 부르는 순간엔 이미 `claimed: true` 이고 `granted_now` 는 빈 배열이다. 그래서 '이 기기가 마지막으로 본 상태'와
    /// 비교해 새로 받은 칸도 알린다.
    /// - `granted_now`(이번 호출이 넣은 행 — 지난주 따라잡기 포함)는 늘 알린다.
    /// - 이번 주 받은 칸 중 `previous` 에 없던 것도 알린다. 단 `previous` 가 아예 없으면(설치 · 로그인 직후 첫 조회) 기준만 잡고
    ///   알리지 않는다 — 며칠 전에 받은 것을 방금 받은 것처럼 말하지 않는다. `previous` 가 지난주 것이면 이번 주 칸은 다 처음 본 것이다.
    /// - 같은 (주, 칸)은 한 번만 센다.
    package static func newGrants(previous: WeeklyWorkSeen?, status: WeeklyWorkStatusDTO) -> [WeeklyWorkStatusDTO.Grant] {
        var result: [WeeklyWorkStatusDTO.Grant] = []
        var keys = Set<String>()
        func add(_ grant: WeeklyWorkStatusDTO.Grant) {
            let week = grant.weekStart ?? status.weekStart ?? ""
            guard keys.insert("\(week)#\(grant.hours)").inserted else { return }
            result.append(grant)
        }
        status.grantedNow.forEach(add)
        if let previous, let week = status.weekStart {
            let already = previous.weekStart == week ? previous.claimedHours : []
            for tier in sortedTiers(status) where tier.claimed && !already.contains(tier.hours) {
                add(.init(hours: tier.hours, ruby: tier.ruby))
            }
        }
        return result
    }

    /// 이번 응답을 본 뒤 저장할 기준(이번 주 받은 칸). 주를 모르면 nil(저장하지 않는다).
    package static func seen(after status: WeeklyWorkStatusDTO) -> WeeklyWorkSeen? {
        guard let week = status.weekStart, !week.isEmpty else { return nil }
        return WeeklyWorkSeen(weekStart: week, claimedHours: Set(sortedTiers(status).filter(\.claimed).map(\.hours)))
    }

    /// 알림 하나로 합친다(빈 배열이면 nil).
    package static func notice(for grants: [WeeklyWorkStatusDTO.Grant]) -> WeeklyWorkGrantNotice? {
        guard !grants.isEmpty else { return nil }
        let ruby = grants.reduce(0) { $0 + $1.ruby }
        guard ruby > 0 else { return nil }
        return WeeklyWorkGrantNotice(ruby: ruby, hours: grants.map(\.hours).sorted())
    }

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

    /// 이 응답의 주가 끝났는가(지금이 다음 주 월요일 0시 이후). 끝났으면 화면 값은 지난주 것이다 — 스로틀 없이 다시 읽는다.
    package static func weekHasRolled(_ status: WeeklyWorkStatusDTO?, now: Date) -> Bool {
        guard let next = kstMidnight(status?.nextWeekStart) else { return false }
        return now >= next
    }

    /// 루비 미러에 서버 잔량을 쓸 것인가 — **더 새 값을 되돌리지 않는다**.
    ///
    /// 미러(`context.gomokuHost.rubyBalance`)는 상점 · 뽑기 · 오목 · 체스가 다 쓰는 한 칸이다. 이 조회가 떠 있는 사이 다른 응답이
    /// 미러를 바꿨으면(예: 뽑기 −50) 그 값이 이 응답보다 늦게 읽힌 값일 수 있다 — 그때 이 응답의 잔량을 쓰면 깎인 루비가
    /// 화면에서 되살아난다. 그래서 **떠날 때와 같을 때만** 쓴다. 쓰지 못했는데 이번에 받은 게 있으면 스토어가 상점을 다시 읽어 맞춘다.
    package static func shouldApplyRuby(server: Int?, atDeparture: Int?, current: Int?) -> Bool {
        guard server != nil else { return false }
        return current == atDeparture
    }

    static let kst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()
}
